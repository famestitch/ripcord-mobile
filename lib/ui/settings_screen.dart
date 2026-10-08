/// Ripcord Preferences dialog ka phone port.
/// Pages (binary se): General | Style | Notifications | Audio | Discord | Proxy | About.
/// Audio page existing VoiceScreen se link hai (dB slider wahi hai).
library;

import 'package:flutter/material.dart';
import 'ripcord_theme.dart';
import 'voice_screen.dart';
import '../session.dart';

class SettingsScreen extends StatelessWidget {
  final RipcordPrefs prefs;
  final Session s;
  const SettingsScreen({super.key, required this.prefs, required this.s});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: prefs,
      builder: (_, __) => ListView(
        children: [
          _header('General'),
          SwitchListTile(title: const Text('Auto-connect on launch'), value: true, onChanged: (_) {}),
          SwitchListTile(title: const Text('Automatically check for updates'), value: true, onChanged: (_) {}),
          SwitchListTile(title: const Text('Avoid creating redundant tabs'), value: true, onChanged: (_) {}),
          _header('Style (Ripcord: fonts, colors, sizes)'),
          SwitchListTile(title: const Text('Dark theme (Ripcord: Dark/Light Theme)'), value: prefs.dark,
              onChanged: (_) => prefs.toggleTheme()),
          ListTile(
              title: const Text('Chat Font size'),
              subtitle: Slider(min: 11, max: 20, divisions: 9, value: prefs.chatFontSize,
                  label: prefs.chatFontSize.toStringAsFixed(0),
                  onChanged: (v) {
                    prefs.chatFontSize = v;
                    prefs.notifyListeners();
                  })),
          ListTile(
              title: const Text('Sidebar Font size'),
              subtitle: Slider(min: 11, max: 18, divisions: 7, value: prefs.sidebarFontSize,
                  label: prefs.sidebarFontSize.toStringAsFixed(0),
                  onChanged: (v) {
                    prefs.sidebarFontSize = v;
                    prefs.notifyListeners();
                  })),
          SwitchListTile(title: const Text('Avatars in Chat'), value: prefs.showAvatars,
              onChanged: (v) {
                prefs.showAvatars = v;
                prefs.notifyListeners();
              }),
          SwitchListTile(title: const Text('Chat Timestamps'), value: prefs.showTimestamps,
              onChanged: (v) {
                prefs.showTimestamps = v;
                prefs.notifyListeners();
              }),
          SwitchListTile(title: const Text('Compact rows (Ripcord feel)'), value: prefs.compact,
              onChanged: (v) {
                prefs.compact = v;
                prefs.notifyListeners();
              }),
          _header('Notifications'),
          SwitchListTile(title: const Text('OS notification popups'), value: true, onChanged: (_) {}),
          SwitchListTile(title: const Text('Sound on mention'), value: true, onChanged: (_) {}),
          _header('Audio (Ripcord Audio page)'),
          ListTile(
              leading: const Icon(Icons.mic),
              title: const Text('Microphone — gain, devices, PTT'),
              subtitle: Text('Current gain: ${s.micGainDb.toStringAsFixed(1)} dB'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => VoiceScreen(
                          s: s,
                          channel: {'name': 'Audio Settings', 'id': s.voiceChannelId ?? ''},
                          voiceServer: s.voiceServer,
                          sessionId: s.voiceSessionId,
                          status: s.voiceStatus,
                          onLeave: () {})))),
          _header('Discord'),
          SwitchListTile(title: const Text('Show my typing indicators'), value: true, onChanged: (_) {}),
          SwitchListTile(title: const Text('Sync read state (mark as read)'), value: true, onChanged: (_) {}),
          _header('Proxy'),
          const ListTile(title: Text('No proxy (direct connection)'), subtitle: Text('HTTP/SOCKS proxy Phase-2')),
          _header('About'),
          ListTile(title: const Text('Ripcord Mobile 0.1.0'),
              subtitle: Text('Logged in as ${s.myName} • NOT affiliated with Discord • 3rd-party use = ban risk')),
        ],
      ),
    );
  }

  Widget _header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(t.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)));
}
