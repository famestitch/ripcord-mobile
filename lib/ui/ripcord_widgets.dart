/// Ripcord sidebar/tree/chat ke reusable phone widgets.
/// Desktop tree → phone: server rail (64px) + channel drawer; right-click → long-press.
library;

import 'package:flutter/material.dart';
import '../session.dart';
import 'ripcord_theme.dart';

String iconUrl(String? guildId, String? hash) =>
    (guildId == null || hash == null) ? '' : 'https://cdn.discordapp.com/icons/$guildId/$hash.png';
String avatarUrl(String? userId, String? hash) =>
    (userId == null || hash == null) ? '' : 'https://cdn.discordapp.com/avatars/$userId/$hash.png';
String emojiUrl(String? id) => id == null ? '' : 'https://cdn.discordapp.com/emojis/$id.png';

// ---------- Server rail (Ripcord sidebar ka leftmost column) ----------
class ServerRail extends StatelessWidget {
  final Session s;
  const ServerRail({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      child: ListView(
        children: [
          const SizedBox(height: 8),
          _railBtn(context, icon: Icons.home, selected: s.guildId == null, onTap: () {}),
          const Divider(),
          for (final g in s.guilds)
            _guildIcon(context, g as Map<String, dynamic>),
        ],
      ),
    );
  }

  Widget _railBtn(BuildContext context, {required IconData icon, required bool selected, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: CircleAvatar(
          backgroundColor: selected ? Colors.white : const Color(0xFF1A1A1A),
          child: Icon(icon, color: selected ? Colors.black : Colors.white),
        ),
      ),
    );
  }

  Widget _guildIcon(BuildContext context, Map<String, dynamic> g) {
    final id = '${g['id']}';
    final sel = s.guildId == id;
    final icon = g['icon'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => s.selectGuild(id),
        child: Row(
          children: [
            Container(width: 4, height: sel ? 32 : 8,
                decoration: BoxDecoration(color: sel ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            CircleAvatar(
              backgroundImage: icon != null ? NetworkImage(iconUrl(id, icon)) : null,
              backgroundColor: sel ? Colors.white : const Color(0xFF1A1A1A),
              child: icon == null
                  ? Text('${(g['name'] ?? '?').toString().substring(0, 1)}',
                      style: TextStyle(color: sel ? Colors.black : Colors.white))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Channel tree (Ripcord sidebar tree replica) ----------
class ChannelTree extends StatelessWidget {
  final Session s;
  final void Function(Map<String, dynamic> channel) onOpenText;
  final void Function(Map<String, dynamic> channel) onJoinVoice;
  const ChannelTree({super.key, required this.s, required this.onOpenText, required this.onJoinVoice});

  @override
  Widget build(BuildContext context) {
    final groups = s.groupedText;
    // categories with parent first, uncategorized ('TEXT CHANNELS') last
    final keys = groups.keys.toList()..sort((a, b) => a == null ? 1 : (b == null ? -1 : s.categoryName(a).compareTo(s.categoryName(b))));
    return ListView(
      children: [
        for (final k in keys) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 2),
            child: Text(s.categoryName(k),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          for (final c in groups[k]!)
            _textRow(context, c as Map<String, dynamic>),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 8, 2),
          child: Text('VOICE CHANNELS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        for (final c in s.voiceChannels) _voiceRow(context, c as Map<String, dynamic>),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _textRow(BuildContext context, Map<String, dynamic> c) {
    final id = '${c['id']}';
    return ListTile(
      dense: true,
      leading: const Icon(Icons.tag, size: 18, color: Colors.grey),
      title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((s.unreadByChannel[id] ?? 0) > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
              child: Text('${s.unreadByChannel[id]}',
                  style: const TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          if (s.isBookmarked(id)) const Icon(Icons.star, size: 14),
        ],
      ),
      onTap: () => onOpenText(c),
      onLongPress: () => _channelMenu(context, c),
    );
  }

  Widget _voiceRow(BuildContext context, Map<String, dynamic> c) {
    final gid = s.guildId ?? '';
    final users = s.voiceUsersIn(gid, '${c['id']}');
    final joined = s.voiceChannelId == '${c['id']}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          selected: joined,
          leading: Icon(Icons.volume_up, size: 18, color: joined ? Colors.white : Colors.grey),
          title: Text('${c['name']}', style: TextStyle(fontWeight: joined ? FontWeight.bold : FontWeight.w500)),
          subtitle: users.isEmpty ? null : Text('${users.length} connected'),
          onTap: () => onJoinVoice(c),
        ),
        // Ripcord: connected users INLINE under voice channel
        for (final u in users)
          Padding(
            padding: const EdgeInsets.only(left: 44, bottom: 2),
            child: Row(
              children: [
                Icon(
                  (u['self_deaf'] ?? false) || (u['deaf'] ?? false)
                      ? Icons.headset_off
                      : (u['self_mute'] ?? false) || (u['mute'] ?? false)
                          ? Icons.mic_off
                          : Icons.mic,
                  size: 14,
                  color: ((u['self_mute'] ?? false) || (u['mute'] ?? false)) ? Colors.grey : Colors.white,
                ),
                const SizedBox(width: 6),
                Flexible(child: Text(s.displayName('${u['user_id']}'), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
    );
  }

  void _channelMenu(BuildContext context, Map<String, dynamic> c) {
    final id = '${c['id']}';
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(s.isBookmarked(id) ? Icons.star : Icons.star_border),
            title: Text(s.isBookmarked(id) ? 'Remove Bookmark' : 'Add Bookmark'),
            onTap: () {
              s.toggleBookmark(s.guildId ?? '', id, '${c['name']}');
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.push_pin),
            title: const Text('Pinned Messages'),
            onTap: () {
              Navigator.pop(context);
              showPins(context, s, id, '${c['name']}');
            },
          ),
        ],
      ),
    );
  }
}

/// Pinned messages sheet (Ripcord: &Pinned Messages per channel)
Future<void> showPins(BuildContext context, Session s, String channelId, String name) async {
  List<dynamic> pins = [];
  try {
    pins = await s.rest.pins(channelId);
  } catch (_) {}
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    builder: (_) => ListView(
      children: [
        ListTile(title: Text('Pinned messages — #$name')),
        for (final p in pins)
          ListTile(
            title: Text('${((p as Map)['author'] as Map?)?['username'] ?? '?'}: ${(p)['content'] ?? ''}'),
          ),
        if (pins.isEmpty) const ListTile(title: Text('No pinned messages')),
      ],
    ),
  );
}

// ---------- Message list (Ripcord author-grouped chat log) ----------
class MessageView extends StatelessWidget {
  final Session s;
  final String channelId;
  final RipcordPrefs prefs;
  final void Function(String replyHint)? onReply;
  const MessageView({super.key, required this.s, required this.channelId, required this.prefs, this.onReply});

  @override
  Widget build(BuildContext context) {
    final msgs = s.messagesByChannel[channelId] ?? [];
    if (msgs.isEmpty) return const Center(child: Text('No messages yet'));
    return ListView.builder(
      reverse: true,
      itemCount: msgs.length,
      itemBuilder: (_, i) {
        final m = msgs[i] as Map<String, dynamic>;
        final prev = i + 1 < msgs.length ? msgs[i + 1] as Map<String, dynamic> : null;
        final sameAuthor = prev != null &&
            '${(prev['author'] as Map?)?['id']}' == '${(m['author'] as Map?)?['id']}';
        return _msgTile(context, m, showHeader: !sameAuthor);
      },
    );
  }

  Widget _msgTile(BuildContext context, Map<String, dynamic> m, {required bool showHeader}) {
    final author = m['author'] as Map<String, dynamic>? ?? {};
    final content = '${m['content'] ?? ''}';
    final ts = '${m['timestamp'] ?? ''}';
    final time = ts.length >= 16 ? ts.substring(11, 16) : ts;
    final edited = (m['edited_timestamp'] as String?) != null;
    final isJumbo = _isSingleEmoji(content);
    final reactions = (m['reactions'] as List?) ?? [];
    final attachments = (m['attachments'] as List?) ?? [];
    final tile = Padding(
      padding: EdgeInsets.only(left: 12, right: 8, top: showHeader ? 10 : 1, bottom: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader && prefs.showAvatars)
            CircleAvatar(
              radius: prefs.avatarSize / 2,
              backgroundImage: author['avatar'] != null ? NetworkImage(avatarUrl('${author['id']}', '${author['avatar']}')) : null,
              child: author['avatar'] == null ? Text('${(author['username'] ?? '?').toString().substring(0, 1)}') : null,
            )
          else
            SizedBox(width: showHeader ? 0 : (prefs.showAvatars ? prefs.avatarSize + 8 : 0)),
          if (showHeader && prefs.showAvatars) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHeader)
                  Row(
                    children: [
                      Flexible(child: Text('${author['username'] ?? '?'}',
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      if (prefs.showTimestamps) ...[
                        const SizedBox(width: 6),
                        Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                      if (edited) const Text(' (edited)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                if (content.isNotEmpty)
                  _richContent(content, jumbo: isJumbo, base: prefs.chatFontSize),
                for (final a in attachments) _attachment(a as Map<String, dynamic>),
                if (reactions.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    children: [for (final r in reactions) _reaction(r as Map<String, dynamic>)],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return InkWell(
      onLongPress: () => _msgMenu(context, m),
      child: tile,
    );
  }

  bool _isSingleEmoji(String t) {
    final graphemes = t.runes.toList();
    return t.trim().isNotEmpty && graphemes.length <= 4 && !t.contains(' ');
  }

  /// Ripcord: mentions highlighted, #channel + URLs clickable-ish, custom :emoji: → CDN image.
  /// Phone v1: mentions bold-colored, custom emoji inline images, URLs tappable text.
  Widget _richContent(String content, {required bool jumbo, required double base}) {
    final emojiRe = RegExp(r'<(a)?:(\w+):(\d+)>');
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in emojiRe.allMatches(content)) {
      if (m.start > last) spans.add(TextSpan(text: content.substring(last, m.start)));
      spans.add(WidgetSpan(
          child: Image.network(emojiUrl(m.group(3)), width: jumbo ? 48 : 22, height: jumbo ? 48 : 22,
              errorBuilder: (_, __, ___) => Text(':${m.group(2)}:'))));
      last = m.end;
    }
    if (last < content.length) spans.add(TextSpan(text: content.substring(last)));
    final mentionRe = RegExp(r'@\w+|#[A-Za-z0-9\-_]+|https?://\S+');
    // simple highlight pass on plain segments
    final out = <InlineSpan>[];
    for (final sp in spans) {
      if (sp is! TextSpan || sp.text == null) {
        out.add(sp);
        continue;
      }
      var t = sp.text!;
      var l = 0;
      for (final mm in mentionRe.allMatches(t)) {
        if (mm.start > l) out.add(TextSpan(text: t.substring(l, mm.start)));
        final word = mm.group(0)!;
        final isLink = word.startsWith('http');
        out.add(TextSpan(
            text: word,
            style: TextStyle(
                color: isLink ? Colors.grey.shade400 : Colors.white,
                fontWeight: isLink ? FontWeight.normal : FontWeight.bold,
                backgroundColor: isLink ? null : Colors.grey.shade900,
                decoration: isLink ? TextDecoration.underline : null)));
        l = mm.end;
      }
      if (l < t.length) out.add(TextSpan(text: t.substring(l)));
    }
    return Text.rich(TextSpan(children: out), style: TextStyle(fontSize: jumbo ? base + 18 : base));
  }

  Widget _attachment(Map<String, dynamic> a) {
    final url = '${a['url'] ?? ''}';
    final name = '${a['filename'] ?? 'file'}';
    final isImg = (a['content_type'] as String?)?.startsWith('image/') ?? url.endsWith('.png') || url.endsWith('.jpg');
    if (isImg && url.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Image.network(url, height: 180, errorBuilder: (_, __, ___) => Text(name)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [const Icon(Icons.attach_file, size: 16), Flexible(child: Text(name))]),
    );
  }

  Widget _reaction(Map<String, dynamic> r) {
    final e = r['emoji'] as Map<String, dynamic>? ?? {};
    final label = '${e['name'] ?? '?'} ${r['count']}';
    return Chip(
      label: e['id'] != null
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Image.network(emojiUrl('${e['id']}'), width: 18, height: 18),
              Text(' ${r['count']}')
            ])
          : Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  void _msgMenu(BuildContext context, Map<String, dynamic> m) {
    final chId = channelId;
    final msgId = '${m['id']}';
    final mine = '${(m['author'] as Map?)?['id']}' == s.myId;
    final ctrl = TextEditingController(text: '${m['content'] ?? ''}');
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Text (Ripcord: Copy Message)'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copy: long-press text to select (native)')));
              }),
          ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy Link to Message'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('discord.com/channels/${s.guildId}/$chId/$msgId')));
              }),
          if (mine) ...[
            ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Message'),
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await showDialog<String>(
                      context: context,
                      builder: (_) => AlertDialog(
                          title: const Text('Edit Message'),
                          content: TextField(controller: ctrl, maxLines: 3),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Save')),
                          ]));
                  if (ok != null) {
                    await s.rest.editMessage(chId, msgId, ok);
                    await s.openChannel(chId);
                  }
                }),
            ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Delete Message'),
                onTap: () async {
                  Navigator.pop(context);
                  await s.rest.deleteMessage(chId, msgId);
                  await s.openChannel(chId);
                }),
          ],
        ],
      ),
    );
  }
}

// ---------- Member list (Ripcord right panel: role/presence grouped) ----------
class MemberList extends StatelessWidget {
  final Session s;
  const MemberList({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    // role order: hoist/high position first (Ripcord roles table order)
    final roles = List.of(s.roles)..sort((a, b) => ((b as Map)['position'] ?? 0).compareTo((a as Map)['position'] ?? 0));
    final Map<String, List<Map<String, dynamic>>> byRole = {};
    final offline = <Map<String, dynamic>>[];
    for (final m in s.members) {
      final mm = m as Map<String, dynamic>;
      // presence REST me nahi aata — gateway GUILD_CREATE se aayega Phase-2 me merge;
      // yahan role grouping dikhate hain (Ripcord jaisa), status grey dot default.
      final rids = (mm['roles'] as List?)?.map((e) => '$e').toList() ?? [];
      String top = 'NO ROLE';
      var topPos = -1;
      for (final r in roles) {
        final rm = r as Map<String, dynamic>;
        if (rids.contains('${rm['id']}') && ((rm['position'] ?? 0) as int) > topPos) {
          topPos = (rm['position'] ?? 0) as int;
          top = '${rm['name']}';
        }
      }
      byRole.putIfAbsent(top, () => []).add(mm);
    }
    return ListView(
      children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('Channel Members', style: TextStyle(fontWeight: FontWeight.bold))),
        // voice-connected members first (Ripcord call lane jaisa)
        if (s.voiceChannelId != null)
          ...s.voiceUsersIn(s.guildId ?? '', s.voiceChannelId!).map((u) => ListTile(
                dense: true,
                leading: const Icon(Icons.volume_up, size: 16),
                title: Text(s.displayName('${u['user_id']}')),
              )),
        for (final entry in byRole.entries) ...[
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 2),
              child: Text('${entry.key} — ${entry.value.length}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey))),
          for (final mm in entry.value)
            ListTile(
              dense: true,
              leading: _memberAvatar(mm),
              title: Text('${(mm['user'] as Map?)?['username'] ?? '?'}${mm['nick'] != null ? ' (${mm['nick']})' : ''}'),
              trailing: Container(width: 10, height: 10,
                  decoration: BoxDecoration(color: presenceColor('offline'), shape: BoxShape.circle)),
              onLongPress: () => _userMenu(context, mm),
            ),
        ],
        if (offline.isNotEmpty) const SizedBox(),
      ],
    );
  }

  Widget _memberAvatar(Map<String, dynamic> mm) {
    final u = mm['user'] as Map<String, dynamic>? ?? {};
    return CircleAvatar(
      radius: 14,
      backgroundImage: u['avatar'] != null ? NetworkImage(avatarUrl('${u['id']}', '${u['avatar']}')) : null,
      child: u['avatar'] == null ? Text('${(u['username'] ?? '?').toString().substring(0, 1)}', style: const TextStyle(fontSize: 12)) : null,
    );
  }

  void _userMenu(BuildContext context, Map<String, dynamic> mm) {
    final u = mm['user'] as Map<String, dynamic>? ?? {};
    final uid = '${u['id']}';
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text('${u['username'] ?? '?'}', style: const TextStyle(fontWeight: FontWeight.bold))),
          ListTile(
              leading: const Icon(Icons.message),
              title: const Text('Open Direct Message (Ripcord: start DM)'),
              onTap: () async {
                Navigator.pop(context);
                await s.rest.openDm(uid);
                await s.reloadAll();
              }),
          ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Name & Tag'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('${u['username'] ?? ''}')));
              }),
        ],
      ),
    );
  }
}

// ---------- Typing bar (Ripcord: "X is typing...") ----------
class TypingBar extends StatelessWidget {
  final Set<String> users;
  const TypingBar({super.key, required this.users});
  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Text('${users.join(', ')} is typing…', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
    );
  }
}

// ---------- Quick switcher (Ripcord Ctrl+K "Go to...") ----------
Future<void> showQuickSwitcher(BuildContext context, Session s, void Function(Map<String, dynamic> c, String gId) open) {
  final ctrl = TextEditingController();
  return showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: const Text('Go to… (Ripcord Ctrl+K)'),
        content: SizedBox(
          width: 320,
          height: 360,
          child: Column(
            children: [
              TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'channel, DM ya user search karo'), onChanged: (_) => setSt(() {})),
              Expanded(
                child: ListView(
                  children: [
                    for (final c in s.channels)
                      if ((c as Map)['name'].toString().toLowerCase().contains(ctrl.text.toLowerCase()))
                        ListTile(
                            dense: true,
                            leading: Icon((c['type'] ?? 0) == 2 ? Icons.volume_up : Icons.tag, size: 16),
                            title: Text('${c['name']}'),
                            onTap: () {
                              Navigator.pop(ctx);
                              open(c, s.guildId ?? '');
                            }),
                    for (final d in s.dms)
                      if (dmName(d).toLowerCase().contains(ctrl.text.toLowerCase()))
                        ListTile(
                            dense: true,
                            leading: const Icon(Icons.person, size: 16),
                            title: Text(dmName(d)),
                            onTap: () {
                              Navigator.pop(ctx);
                              open(<String, dynamic>{'id': (d as Map)['id'], 'name': dmName(d), 'type': 1}, '');
                            }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Voice bottom bar label — region change ke waqt status bhi (mono grey text me).
String _voiceBarLabel(Session s, String chName, int n) {
  final base = '$chName • $n in voice';
  if (s.voiceStatus == 'connected' || s.voiceStatus == 'idle') return base;
  return '$base • ${s.voiceStatus}';
}

String dmName(dynamic d) {
  final m = d as Map<String, dynamic>;
  final rec = (m['recipients'] as List?) ?? [];
  if (rec.isEmpty) return 'DM ${m['id']}';
  return rec.map((u) => '${(u as Map)['username']}').join(', ');
}

// ---------- Persistent voice bottom bar (Ripcord call lane) ----------
class VoiceBottomBar extends StatelessWidget {
  final Session s;
  final VoidCallback onExpand;
  const VoiceBottomBar({super.key, required this.s, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    if (s.voiceChannelId == null) return const SizedBox.shrink();
    String chName = s.voiceChannelId!;
    for (final c in s.channels) {
      if ('${(c as Map)['id']}' == s.voiceChannelId) chName = '${c['name']}';
    }
    final users = s.voiceUsersIn(s.voiceGuildId ?? '', s.voiceChannelId!);
    return InkWell(
      onTap: onExpand,
      child: Container(
        decoration: const BoxDecoration(
            color: Colors.black, border: Border(top: BorderSide(color: Colors.white, width: 1))),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.volume_up, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_voiceBarLabel(s, chName, users.length))),
            IconButton(
                icon: Icon(s.voiceMuted ? Icons.mic_off : Icons.mic, size: 20),
                onPressed: () => s.toggleVoiceMute()),
            IconButton(
                icon: const Icon(Icons.call_end, size: 20),
                onPressed: () => s.leaveVoice()),
          ],
        ),
      ),
    );
  }
}
