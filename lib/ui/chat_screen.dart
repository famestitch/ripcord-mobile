/// Channel chat screen — Ripcord center tab ka phone version:
/// toolbar (pins/members/bell) + grouped messages + typing bar + input with @/:emoji: completion.
library;

import 'package:flutter/material.dart';
import '../session.dart';
import 'ripcord_theme.dart';
import 'ripcord_widgets.dart';

class ChatScreen extends StatefulWidget {
  final Session s;
  final RipcordPrefs prefs;
  final Map<String, dynamic> channel;
  final String guildId;
  const ChatScreen({super.key, required this.s, required this.prefs, required this.channel, required this.guildId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  List<String> _completions = [];
  bool _muted = false;

  String get chId => '${widget.channel['id']}';
  String get chName => '${widget.channel['name'] ?? 'channel'}';

  @override
  void initState() {
    super.initState();
    widget.s.openChannel(chId);
    _ctrl.addListener(_updateCompletion);
  }

  /// Ripcord tab-completion: @user aur :emoji: popup
  void _updateCompletion() {
    final text = _ctrl.text;
    final at = RegExp(r'@(\w*)$').firstMatch(text);
    final em = RegExp(r':(\w*)$').firstMatch(text);
    List<String> out = [];
    if (at != null) {
      final q = at.group(1)!.toLowerCase();
      for (final m in widget.s.members) {
        final u = (m as Map<String, dynamic>)['user'] as Map<String, dynamic>? ?? {};
        final name = '${u['username'] ?? ''}';
        if (name.toLowerCase().startsWith(q)) out.add('@$name');
        if (out.length >= 6) break;
      }
    } else if (em != null) {
      const common = ['smile', 'laugh', 'thumbsup', 'heart', 'fire', 'clap', 'eyes', 'tada'];
      final q = em.group(1)!.toLowerCase();
      out = common.where((e) => e.startsWith(q)).map((e) => ':$e:').toList();
    }
    if (out.join() != _completions.join()) setState(() => _completions = out);
  }

  void _applyCompletion(String c) {
    final text = _ctrl.text;
    final done = text.replaceFirst(RegExp(r'(@\w*|:[\w]*)$'), c);
    _ctrl.text = '$done ';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.s,
      builder: (_, __) => Scaffold(
        appBar: AppBar(
          title: Text('# $chName'),
          actions: [
            IconButton(icon: const Icon(Icons.push_pin), tooltip: 'Pinned Messages',
                onPressed: () => showPins(context, widget.s, chId, chName)),
            IconButton(icon: Icon(_muted ? Icons.notifications_off : Icons.notifications_active),
                tooltip: 'Mute channel', onPressed: () => setState(() => _muted = !_muted)),
            IconButton(
                icon: const Icon(Icons.bookmark_border),
                tooltip: 'Bookmark',
                onPressed: () => widget.s.toggleBookmark(widget.guildId, chId, chName)),
          ],
        ),
        endDrawer: Drawer(child: SafeArea(child: MemberList(s: widget.s))),
        body: Column(
          children: [
            if (widget.s.loadingOlder.contains(chId))
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                // Ripcord infinite scroll: upar khincho to purane messages
                onNotification: (n) {
                  if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
                    widget.s.loadOlder(chId);
                  }
                  return false;
                },
                child: MessageView(s: widget.s, channelId: chId, prefs: widget.prefs),
              ),
            ),
            TypingBar(users: widget.s.typingByChannel[chId] ?? {}),
            if (_completions.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [for (final c in _completions) Padding(padding: const EdgeInsets.all(4), child: ActionChip(label: Text(c), onPressed: () => _applyCompletion(c)))],
                ),
              ),
            _inputRow(),
          ],
        ),
      ),
    );
  }

  Widget _inputRow() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Attach file (Ripcord: Attach Files)',
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('File upload Phase-2: /channels/:id/attachments (TODO)')))),
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4, // Ripcord: input auto-resize
                decoration: InputDecoration(hintText: 'Message #$chName', border: const OutlineInputBorder()),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                onChanged: (_) => widget.s.noteTyping(chId), // throttled typing event
              ),
            ),
            IconButton(icon: const Icon(Icons.send), onPressed: _send),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final t = _ctrl.text;
    _ctrl.clear();
    setState(() => _completions = []);
    try {
      await widget.s.send(chId, t);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send fail: $e (rate-limit ho to 2 sec rukke bhejo)')));
      _ctrl.text = t; // text wapas taaki dobara bhej sako
    }
  }

  @override
  void dispose() {
    widget.s.closeChannel();
    _ctrl.dispose();
    super.dispose();
  }
}
