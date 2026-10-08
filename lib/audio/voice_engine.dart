/// Voice engine: Ripcord PC pipeline ka phone port.
/// PC: QAudioInput(WASAPI, float 48k mono) -> opus_encode_float -> sodium encrypt -> UDP
/// Phone: record plugin (16k/48k) -> resample 48k mono float -> Opus -> UDP
///
/// NOTE: ye signalling + gain + gate + Opus-params layer hai (pure Dart, testable).
/// Asli UDP socket + AudioRecord/AudioTrack wiring Android (Kotlin/Oboe) / iOS
/// native module me hogi — interface neeche diya hai taaki UI abhi se ban jaye.
library;

import 'gain.dart';

enum OpusMode { voice, music }

class VoiceEngineConfig {
  /// Ripcord: "Force Opus codec to encode in music mode" checkbox ka equivalent.
  /// music = zyada bitrate, voice (speech) optimization off. Default voice.
  OpusMode opusMode = OpusMode.voice;

  /// Ripcord RipLogScaleDbSlider: 0..24 dB mic gain
  double micGainDb = 0.0;

  /// Voice Activity gate threshold 0.0..1.0 (gateThresholdChangedByGui)
  double gateThreshold = 0.15;

  bool pushToTalk = false;
  bool pttPressed = false;
  bool muted = false;
  bool deafen = false;

  int sampleRate = 48000;
  int channels = 1;
  int frameMs = 20; // 960 samples @48k

  int targetBitrate() => opusMode == OpusMode.music ? 128000 : 64000;
  bool get shouldTransmit => muted ? false : (pushToTalk ? pttPressed : true);
}

class VoiceEngine {
  final VoiceEngineConfig cfg = VoiceEngineConfig();
  Function(List<double> pcm48kMono, bool voiceActive)? onMicFrame;

  /// Mic se aaya frame (float -1..1, 48k mono) -> gain -> gate -> callback
  /// Return: transmit karna hai ya nahi (gate/PTT/mute ke hisaab se)
  bool processMicFrame(List<double> frame) {
    if (!cfg.shouldTransmit || cfg.deafen) return false;
    final boosted = applyMicGain(frame, cfg.micGainDb);
    final peak = boosted.fold<double>(0.0, (m, s) => s.abs() > m ? s.abs() : m);
    final voiceActive = peak >= cfg.gateThreshold;
    // +24dB par gate threshold badhana padta hai — UI me hint dikhao (neeche screen me hai)
    if (voiceActive) onMicFrame?.call(boosted, true);
    return voiceActive;
  }

  void setGainDb(double db) => cfg.micGainDb = db.clamp(0.0, 24.0);
  void setMusicMode(bool music) => cfg.opusMode = music ? OpusMode.music : OpusMode.voice;
}
