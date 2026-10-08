/// LOUDMIC — real voice media backend: mic -> +gain -> Opus -> encrypt -> UDP.
/// Yahi app ka core hai (Ripcord ka mic-gain concept, phone par real).
///
/// Chain (TX): record(mic, 48kHz mono PCM16, echoCancel+noiseSuppress)
///   -> float -> applyMicGain (0..+24dB, gain.dart) -> gate check
///   -> SimpleOpusEncoder.encodeFloat (20ms/960) -> encrypt -> VoiceConnection UDP.
///
/// Chain (RX): decrypt -> SimpleOpusDecoder.decodeFloat -> PCM stream
///   (speaker playback wiring Phase-2b: stream ready hai, AudioTrack baki).
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:opus_dart/opus_dart.dart' as opus;
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:record/record.dart';
import 'package:sodium/sodium.dart';
import '../audio/gain.dart';
import 'voice_audio_backend.dart';

class LoudMicBackend extends VoiceAudioBackend {
  static bool _libsReady = false;
  static Future<void>? _initFuture;
  static Sodium? _sodium;

  opus.SimpleOpusEncoder? _enc;
  opus.SimpleOpusDecoder? _dec;
  AudioRecorder? _rec;
  StreamSubscription<Uint8List>? _sub;
  void Function(PcmFrame pcm48kMono)? _onFrame;

  /// 960-sample frame accumulator (mic chunks arbitrary size me aate hain).
  final List<double> _acc = [];

  /// Ripcord jaisa real-time feel: slider ghoomate hi gain agle 20ms frame se
  /// lagta hai, lekin smoothing ke saath (izit zipper-noise/click nahi).
  double _appliedGainDb = 0.0;

  /// On-device proof: post-gain mic level (dBFS). VoiceScreen me live meter.
  @override
  final ValueNotifier<double> micLevelDb = ValueNotifier(-60.0);

  /// Ek baar: libopus load + libsodium init. Dobara call safe hai.
  static Future<void> ensureInitialized() {
    _initFuture ??= _initLibs();
    return _initFuture!;
  }

  static Future<void> _initLibs() async {
    opus.initOpus(await opus_flutter.load());
    _sodium = await SodiumInit.init();
    _libsReady = true;
  }

  void _makeEncoder() {
    _enc?.destroy();
    _enc = opus.SimpleOpusEncoder(
      sampleRate: 48000,
      channels: 1,
      // musicMode = broadcast quality (Ripcord "music mode" checkbox),
      // voice = speech-optimized (default).
      application: musicMode ? opus.Application.audio : opus.Application.voip,
    );
  }

  /// Slider drag par har tick me encoder recreate NA ho (voice kategi) —
  /// sirf mode badalne par recreate.
  @override
  Future<void> setMusicMode(bool music) async {
    if (music == musicMode && _enc != null) return;
    musicMode = music;
    if (_enc != null) _makeEncoder();
  }

  @override
  Future<void> startCapture(void Function(PcmFrame pcm48kMono) onFrame) async {
    await ensureInitialized();
    if (_sub != null) {
      _onFrame = onFrame;
      return;
    }
    _onFrame = onFrame;
    _makeEncoder();
    _dec ??= opus.SimpleOpusDecoder(sampleRate: 48000, channels: 1);
    _rec = AudioRecorder();
    if (!await _rec!.hasPermission()) {
      throw Exception('Mic permission denied — phone settings me allow karo');
    }
    // RAW LOUD: OS ki saari processing OFF — no echo-cancel, no noise-suppress,
    // no autoGain. Sirf hamara +24dB log-gain lagta hai (user demand: raw loud).
    // Note: kuch phones hardware-level thoda processing force karte hain (record
    // plugin ke bahar hai) — lekin Dart-said se ye maximum raw hai.
    final stream = await _rec!.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 48000,
      numChannels: 1,
      autoGain: false,
      echoCancel: false,
      noiseSuppress: false,
    ));
    _sub = stream.listen(_onChunk, onError: (_) {}, cancelOnError: false);
  }

  void _onChunk(Uint8List bytes) {
    if (bytes.length < 2) return;
    // Mono PCM16LE manga hai (numChannels: 1) — seedha float me badlo.
    final bd = ByteData.sublistView(bytes);
    final n = (bytes.length ~/ 2);
    for (var i = 0; i < n; i++) {
      _acc.add(bd.getInt16(i * 2, Endian.little) / 32768.0);
    }
    while (_acc.length >= 960) {
      final frame = _acc.sublist(0, 960);
      _acc.removeRange(0, 960);
      // LOUDMIC: Ripcord-style log gain yahan lagta hai — target ki taraf
      // tezi se ramp (real-time + click-free).
      _appliedGainDb += (gainDb - _appliedGainDb) * 0.5;
      if ((_appliedGainDb - gainDb).abs() < 0.05) _appliedGainDb = gainDb;
      final boosted = applyMicGain(frame, _appliedGainDb);
      var peak = 0.0;
      for (final v in boosted) {
        final a = v.abs();
        if (a > peak) peak = a;
      }
      micLevelDb.value = peak <= 0 ? -60.0 : (20 * math.log(peak) / math.ln10).clamp(-60.0, 0.0);
      // Voice gate (Ripcord gateThreshold): khamoshi par encode hi nahi.
      if (peak < gateThreshold) continue;
      _onFrame?.call(boosted);
    }
  }

  @override
  Future<void> stopCapture() async {
    _onFrame = null;
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      await _rec?.stop();
    } catch (_) {}
    try {
      _rec?.dispose();
    } catch (_) {}
    _rec = null;
    _acc.clear();
    try {
      _enc?.destroy();
    } catch (_) {}
    _enc = null;
  }

  @override
  List<int> encodeOpus(PcmFrame pcm) {
    if (!_libsReady || _enc == null) throw StateError('opus not ready');
    final out = _enc!.encodeFloat(input: Float32List.fromList(pcm));
    if (out.isEmpty) return const [];
    return out;
  }

  @override
  PcmFrame decodeOpus(List<int> packet) {
    if (!_libsReady) throw StateError('opus not ready');
    _dec ??= opus.SimpleOpusDecoder(sampleRate: 48000, channels: 1);
    return _dec!.decodeFloat(input: Uint8List.fromList(packet)).toList();
  }

  SecureKey _key(Uint8List secret) => SecureKey.fromList(_sodium!, secret);

  @override
  Uint8List encryptRtp(Uint8List rtpHeader12, List<int> opusPayload, Uint8List secretKey, String mode) {
    if (!_libsReady) throw StateError('sodium not ready');
    final key = _key(secretKey);
    try {
      if (mode == 'xsalsa20_poly1305') {
        // nonce = header(12B) + 12 zero bytes, koi suffix nahi.
        final nonce = Uint8List(24)..setRange(0, 12, rtpHeader12);
        final ct = _sodium!.crypto.secretBox.easy(
            message: Uint8List.fromList(opusPayload), nonce: nonce, key: key);
        return Uint8List.fromList([...rtpHeader12, ...ct]);
      }
      if (mode == 'xsalsa20_poly1305_suffix') {
        final nonce = _sodium!.randombytes.buf(24);
        final ct = _sodium!.crypto.secretBox.easy(
            message: Uint8List.fromList(opusPayload), nonce: nonce, key: key);
        return Uint8List.fromList([...rtpHeader12, ...ct, ...nonce]);
      }
      if (mode == 'aead_xchacha20_poly1305_rtpsize') {
        // Discord rtpsize: 4B random suffix; nonce24 = 20 zero + suffix; header = AAD.
        final suffix = _sodium!.randombytes.buf(4);
        final nonce = Uint8List(24)..setRange(20, 24, suffix);
        final ct = _sodium!.crypto.aeadXChaCha20Poly1305IETF.encrypt(
            message: Uint8List.fromList(opusPayload),
            nonce: nonce,
            additionalData: rtpHeader12,
            key: key);
        return Uint8List.fromList([...rtpHeader12, ...ct, ...suffix]);
      }
      throw UnsupportedError('encrypt mode not supported: $mode (aead_aes256_gcm package:sodium me nahi hai)');
    } finally {
      key.dispose();
    }
  }

  @override
  (Uint8List, List<int>) decryptRtp(Uint8List packet, Uint8List secretKey, String mode) {
    if (!_libsReady) throw StateError('sodium not ready');
    if (packet.length < 12) throw ArgumentError('packet too short');
    final header = Uint8List.sublistView(packet, 0, 12);
    final key = _key(secretKey);
    try {
      if (mode == 'xsalsa20_poly1305') {
        final nonce = Uint8List(24)..setRange(0, 12, header);
        final pt = _sodium!.crypto.secretBox.openEasy(
            cipherText: Uint8List.sublistView(packet, 12), nonce: nonce, key: key);
        return (Uint8List.fromList(header), pt);
      }
      if (mode == 'xsalsa20_poly1305_suffix') {
        if (packet.length < 12 + 24) throw ArgumentError('suffix packet too short');
        final nonce = Uint8List.sublistView(packet, packet.length - 24);
        final pt = _sodium!.crypto.secretBox.openEasy(
            cipherText: Uint8List.sublistView(packet, 12, packet.length - 24),
            nonce: nonce,
            key: key);
        return (Uint8List.fromList(header), pt);
      }
      if (mode == 'aead_xchacha20_poly1305_rtpsize') {
        if (packet.length < 12 + 4) throw ArgumentError('rtpsize packet too short');
        final suffix = Uint8List.sublistView(packet, packet.length - 4);
        final nonce = Uint8List(24)..setRange(20, 24, suffix);
        final pt = _sodium!.crypto.aeadXChaCha20Poly1305IETF.decrypt(
            cipherText: Uint8List.sublistView(packet, 12, packet.length - 4),
            nonce: nonce,
            additionalData: Uint8List.fromList(header),
            key: key);
        return (Uint8List.fromList(header), pt);
      }
      throw UnsupportedError('decrypt mode not supported: $mode');
    } finally {
      key.dispose();
    }
  }
}
