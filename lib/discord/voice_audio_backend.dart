/// Voice audio backend interface — mic <-> Opus <-> encrypt.
/// Real implementation: LoudMicBackend (mic + gain + opus + sodium, pub packages).
library;

import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// 20ms PCM frame @48kHz mono float (-1..1). 960 samples.
typedef PcmFrame = List<double>;

abstract class VoiceAudioBackend {
  /// Ripcord dB gain 0..24 (UI slider → Session → yahan). TX me lagta hai.
  double gainDb = 0.0;

  /// Voice-activity gate 0..0.5 (is se neeche peak = khamoshi, encode nahi).
  double gateThreshold = 0.15;

  /// Ripcord "music mode": Opus audio-app + zyada bitrate feel (encoder recreate).
  bool musicMode = false;
  Future<void> setMusicMode(bool music) async {
    musicMode = music;
  }

  /// Post-gain mic level dBFS (UI meter ke liye). -60 = silence.
  final ValueNotifier<double> micLevelDb = ValueNotifier(-60.0);

  /// Mic capture shuru karo. Gate-pass frames par onFrame call hoga (960 float).
  Future<void> startCapture(void Function(PcmFrame pcm48kMono) onFrame);

  Future<void> stopCapture();

  /// PCM 960 samples -> Opus packet bytes. Gated silence par EMPTY list.
  List<int> encodeOpus(PcmFrame pcm);

  /// Opus packet bytes -> PCM 960 samples (remote users ke liye).
  PcmFrame decodeOpus(List<int> packet);

  /// 12-byte RTP header + Opus payload -> encrypted UDP packet.
  /// mode: 'aead_aes256_gcm_rtpsize' | 'xsalsa20_poly1305_suffix' | 'xsalsa20_poly1305'
  /// Nonce rules (libsodium, SESSION_DESCRIPTION se mila secret_key):
  /// - xsalsa20_poly1305: nonce = header(12B) + 12 zero bytes, koi suffix nahi.
  /// - xsalsa20_poly1305_suffix: 24 random bytes suffix, wahi nonce.
  /// - aead_aes256_gcm_rtpsize: 4 random bytes suffix.
  /// - aead_xchacha20_poly1305_rtpsize: 4 random bytes suffix.
  Uint8List encryptRtp(Uint8List rtpHeader12, List<int> opusPayload, Uint8List secretKey, String mode);

  /// Encrypted UDP packet -> (header12, opusPayload). Mode connection se pata hai.
  (Uint8List, List<int>) decryptRtp(Uint8List packet, Uint8List secretKey, String mode);
}

/// Default backend — saaf error ke saath fail hota hai.
/// Connection manager isko dekh kar 'audio-backend-missing' status me jata hai
/// aur native wiring judte hi khud start ho jata hai (rejoin ki zarurat nahi).
class StubVoiceAudioBackend implements VoiceAudioBackend {
  static const msg =
      'Native audio backend wired nahi: libopus (encode/decode) + libsodium (encrypt) '
      'ka FFI chahiye. Transport (region bypass/resume/rejoin) phir bhi live hai.';

  @override
  Future<void> startCapture(void Function(PcmFrame pcm48kMono) onFrame) async {
    throw UnimplementedError(msg);
  }

  @override
  Future<void> stopCapture() async {}

  @override
  List<int> encodeOpus(PcmFrame pcm) => throw UnimplementedError(msg);

  @override
  PcmFrame decodeOpus(List<int> packet) => throw UnimplementedError(msg);

  @override
  Uint8List encryptRtp(Uint8List rtpHeader12, List<int> opusPayload, Uint8List secretKey, String mode) =>
      throw UnimplementedError(msg);

  @override
  (Uint8List, List<int>) decryptRtp(Uint8List packet, Uint8List secretKey, String mode) =>
      throw UnimplementedError(msg);
}

/// Sirf LOCAL loopback test ke liye (encrypt = plain copy). DISCORD PAR KABHI NA BHEJO
/// — server decrypt fail karega. Transport/migration logic ko bina native ke
/// test karne ke kaam ka hai.
class PassthroughTestBackend extends StubVoiceAudioBackend {
  PcmFrame? lastTx;
  @override
  Future<void> startCapture(void Function(PcmFrame pcm48kMono) onFrame) async {}

  @override
  List<int> encodeOpus(PcmFrame pcm) {
    lastTx = pcm;
    return [0xFF]; // fake 1-byte payload
  }

  @override
  Uint8List encryptRtp(Uint8List rtpHeader12, List<int> opusPayload, Uint8List secretKey, String mode) {
    return Uint8List.fromList([...rtpHeader12, ...opusPayload]);
  }
}
