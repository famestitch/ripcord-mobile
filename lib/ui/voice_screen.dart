import 'package:flutter/material.dart';
import '../audio/gain.dart';
import '../session.dart';

/// LOUDMIC screen — Ripcord Audio Settings ka phone version, Session se judha.
/// Sliders seedha Session me likhte hain → backend (mic gain/gate/music) live update.
/// Neeche LIVE mic level meter hai — on-device proof ki loudmic kaam kar raha hai.
class VoiceScreen extends StatelessWidget {
  final Session s;
  final Map<String, dynamic> channel;
  final Map<String, dynamic>? voiceServer;
  final String? sessionId;
  final String status;
  final VoidCallback onLeave;
  const VoiceScreen(
      {super.key,
      required this.s,
      required this.channel,
      required this.voiceServer,
      required this.sessionId,
      this.status = 'connecting',
      required this.onLeave});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (_, __) {
        final db = s.micGainDb;
        final lin = dbToLinear(db);
        return Scaffold(
          appBar: AppBar(title: Text('${channel['name']}')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                _levelMeter(),
                const SizedBox(height: 8),
                Text('Mic Gain: ${db.toStringAsFixed(1)} dB  (x${lin.toStringAsFixed(2)})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Slider(
                  min: 0,
                  max: 1,
                  divisions: 100,
                  value: dbToSlider(db),
                  label: '${db.toStringAsFixed(1)} dB',
                  onChanged: (t) {
                    s.micGainDb = sliderToDb(t).clamp(0.0, 24.0);
                    s.syncAudioToBackend();
                  },
                ),
                const Text('0 dB ───────────── +24 dB (Ripcord jaisa log-scale)'),
                if (db >= 18)
                  const Text('Note: +18dB se upar gate threshold badhao warna noise trigger hoga.',
                      style: TextStyle(color: Colors.grey)),
                const Divider(),
                SwitchListTile(
                  title: const Text('Music mode (Opus)'),
                  subtitle: const Text(
                      'Do not enable unless broadcasting music — voice quality ghategi (Ripcord wali warning).'),
                  value: s.musicMode,
                  onChanged: (v) {
                    s.musicMode = v;
                    s.syncAudioToBackend();
                  },
                ),
                ListTile(
                  title: const Text('Voice Activity gate'),
                  subtitle: Slider(
                    min: 0,
                    max: 0.5,
                    divisions: 50,
                    value: s.gateThreshold,
                    label: s.gateThreshold.toStringAsFixed(2),
                    onChanged: (v) {
                      s.gateThreshold = v;
                      s.syncAudioToBackend();
                    },
                  ),
                ),
                SwitchListTile(
                    title: const Text('Mute'),
                    value: s.voiceMuted,
                    onChanged: (_) => s.toggleVoiceMute()),
                const Divider(),
                Text('Bitrate: auto (Opus default) • 48kHz mono • 20ms frame',
                    style: const TextStyle(color: Colors.grey)),
                Text('Voice server: ${voiceServer?['endpoint'] ?? 'connecting…'}',
                    style: const TextStyle(color: Colors.grey)),
                Text('Status: $status — region change par mic/encoder live rehte hain',
                    style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              onPressed: () {
                onLeave();
                Navigator.pop(context);
              },
              child: const Text('Disconnect'),
            ),
          ),
        );
      },
    );
  }

  /// Live mic level — bolo to bar badhega (post-gain dBFS). B&W text meter.
  Widget _levelMeter() {
    return AnimatedBuilder(
      animation: s.audioBackend.micLevelDb,
      builder: (ctx, ___) {
        final double db = s.audioBackend.micLevelDb.value;
        final double frac = ((db + 60.0) / 60.0).clamp(0.0, 1.0);
        final int bars = (frac * 20.0).round();
        final StringBuffer buf = StringBuffer("MIC LEVEL  ");
        for (int i = 0; i < 20; i++) {
          buf.write(i < bars ? "#" : "-");
        }
        buf.write("  ");
        buf.write(db.toStringAsFixed(0));
        buf.write(" dB");
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(buf.toString(), style: const TextStyle(fontFamily: "monospace", fontSize: 12)),
            const Text("Meter hile = mic + gain live hai (Discord transmit ready)",
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        );
      },
    );
  }
}
