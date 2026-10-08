/// Home shell — Ripcord main window ka phone mapping:
/// menu bar → AppBar+menu | sidebar tree → ServerRail + channel drawer |
/// tabs → bottom nav | Ctrl+K → search button | call lane → VoiceBottomBar.
library;

import 'package:flutter/material.dart';
import '../session.dart';
import 'ripcord_theme.dart';
import 'ripcord_widgets.dart';
import 'chat_screen.dart';
import 'tabs_screens.dart';
import 'settings_screen.dart';
import 'voice_screen.dart';

class HomeScreen extends StatefulWidget {
  final Session session;
  final RipcordPrefs prefs;
  const HomeScreen({super.key, required this.session, required this.prefs});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0; // 0 Chats | 1 Bookmarks | 2 Mentions | 3 Friends | 4 Settings
  Session get s => widget.session;

  void _openText(Map<String, dynamic> c, String gId) {
    final gid = gId.isNotEmpty ? gId : (s.guildId ?? '');
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatScreen(s: s, prefs: widget.prefs, channel: c, guildId: gid)));
  }

  void _joinVoice(Map<String, dynamic> c) {
    final gid = s.guildId ?? '';
    if (gid.isEmpty) return;
    s.joinVoice(gid, '${c['id']}');
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AnimatedBuilder(
                  animation: s,
                  builder: (_, __) => VoiceScreen(
                      s: s,
                      channel: c,
                      voiceServer: s.voiceServer,
                      sessionId: s.voiceSessionId,
                      status: s.voiceStatus,
                      onLeave: () => s.leaveVoice()),
                )));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (_, __) => Scaffold(
        appBar: AppBar(
          title: Text(_title() + (s.gatewayStatus == 'connected' ? '' : ' • ${s.gatewayStatus}')),
          actions: [
            IconButton(icon: const Icon(Icons.search), tooltip: 'Go to… (Ripcord Ctrl+K)',
                onPressed: () => showQuickSwitcher(context, s, _openText)),
            PopupMenuButton<String>(
              tooltip: 'Ripcord menu',
              onSelected: (v) {
                if (v == 'reload') s.reloadAll();
                if (v == 'leave_voice') s.leaveVoice();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'reload', child: Text('Refresh (reload all)')),
                PopupMenuItem(value: 'leave_voice', child: Text('Disconnect voice')),
              ],
            ),
          ],
        ),
        drawer: s.guildId == null
            ? null
            : Drawer(
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_guildName(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      const Divider(height: 1),
                      Expanded(child: ChannelTree(s: s, onOpenText: (c) => _openText(c, s.guildId ?? ''), onJoinVoice: _joinVoice)),
                    ],
                  ),
                ),
              ),
        body: Row(
          children: [
            ServerRail(s: s),
            Expanded(child: _body()),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VoiceBottomBar(s: s, onExpand: () {
              if (s.voiceChannelId == null) return;
              _joinVoice({'id': s.voiceChannelId, 'name': 'Voice'});
            }),
            NavigationBar(
              selectedIndex: _tab,
              height: 62,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                const NavigationDestination(icon: Icon(Icons.chat), label: 'Chats'),
                NavigationDestination(
                    icon: _badged(context, const Icon(Icons.star), s.bookmarks.length),
                    label: 'Saved'),
                NavigationDestination(
                    icon: _badged(context, const Icon(Icons.alternate_email), s.mentions.length),
                    label: 'Mentions'),
                const NavigationDestination(icon: Icon(Icons.people), label: 'Friends'),
                const NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _title() {
    if (_tab == 1) return 'Bookmarks';
    if (_tab == 2) return '@ Mentions';
    if (_tab == 3) return 'Friends & DMs';
    if (_tab == 4) return 'Preferences';
    return _guildName();
  }

  String _guildName() {
    for (final g in s.guilds) {
      if ('${(g as Map)['id']}' == s.guildId) return '${g['name']}';
    }
    return s.myName;
  }

  /// Ripcord unread/mention badge — purane Flutter SDK par bhi chalne wala custom badge
  /// (material Badge widget nahi use kiya taaki Flutter 3.2+ sab par chale).
  Widget _badged(BuildContext context, Icon icon, int count) {
    if (count == 0) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -8,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Text('$count', style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _body() {
    switch (_tab) {
      case 1:
        return BookmarksScreen(s: s, onOpen: _openText);
      case 2:
        return MentionsScreen(s: s, onOpen: _openText);
      case 3:
        return FriendsScreen(s: s, onOpenDm: (c, g) => _openText(c, g));
      case 4:
        return SettingsScreen(prefs: widget.prefs, s: s);
      default:
        if (s.guildId == null) {
          return const Center(child: Text('Server rail se server chuno\n(drawer me channels milenge)'));
        }
        return ChannelTree(s: s, onOpenText: (c) => _openText(c, s.guildId ?? ''), onJoinVoice: _joinVoice);
    }
  }
}
