/// Ripcord ke tab-views ka phone version: Bookmarks, Mentions, Friends/DMs.
library;

import 'package:flutter/material.dart';
import '../session.dart';
import 'ripcord_widgets.dart';

// ---------- Bookmarks (Ripcord sidebar top section) ----------
class BookmarksScreen extends StatelessWidget {
  final Session s;
  final void Function(Map<String, dynamic> c, String gId) onOpen;
  const BookmarksScreen({super.key, required this.s, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    if (s.bookmarks.isEmpty) {
      return const Center(
          child: Text('Koi bookmark nahi.\nChannel par long-press → Add Bookmark (Ripcord jaisa)',
              textAlign: TextAlign.center));
    }
    return ListView(
      children: [
        for (final b in s.bookmarks)
          ListTile(
            leading: const Icon(Icons.star),
            title: Text('${b['name']}'),
            trailing: IconButton(
                icon: const Icon(Icons.star),
                onPressed: () => s.toggleBookmark(b['guildId']!, b['channelId']!, b['name']!)),
            onTap: () => onOpen({'id': b['channelId'], 'name': b['name'], 'type': 0}, b['guildId']!),
          ),
      ],
    );
  }
}

// ---------- Mentions (Ripcord Notifications/Mentions tab) ----------
class MentionsScreen extends StatelessWidget {
  final Session s;
  final void Function(Map<String, dynamic> c, String gId) onOpen;
  const MentionsScreen({super.key, required this.s, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    if (s.mentions.isEmpty) {
      return const Center(child: Text('Koi mention nahi.\nJab koi @you karega, yahan aayega.'));
    }
    return ListView.builder(
      itemCount: s.mentions.length,
      itemBuilder: (_, i) {
        final e = s.mentions[i];
        final m = e['msg'] as Map<String, dynamic>;
        return ListTile(
          leading: const Icon(Icons.alternate_email),
          title: Text('${(m['author'] as Map?)?['username'] ?? '?'}: ${m['content'] ?? ''}',
              maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${m['timestamp'] ?? ''}'),
          onTap: () => onOpen(
              {'id': e['channel_id'], 'name': 'mention', 'type': 0}, '${e['guild_id'] ?? ''}'),
        );
      },
    );
  }
}

// ---------- Friends + DMs (Ripcord Friends tab + DM open/close) ----------
class FriendsScreen extends StatelessWidget {
  final Session s;
  final void Function(Map<String, dynamic> c, String gId) onOpenDm;
  const FriendsScreen({super.key, required this.s, required this.onOpenDm});

  @override
  Widget build(BuildContext context) {
    final accepted = s.friends.where((f) => (f as Map)['type'] == 1).toList();
    final pending = s.friends.where((f) => (f as Map)['type'] == 2 || (f as Map)['type'] == 3).toList();
    return ListView(
      children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('DIRECT MESSAGES', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
        for (final d in s.dms)
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(dmName(d)),
            onTap: () {
              final m = d as Map<String, dynamic>;
              onOpenDm({'id': '${m['id']}', 'name': dmName(d), 'type': 1}, '');
            },
          ),
        const Padding(padding: EdgeInsets.all(12), child: Text('FRIENDS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
        for (final f in accepted)
          Builder(builder: (_) {
            final u = (f as Map)['user'] as Map? ?? {};
            return ListTile(
              leading: CircleAvatar(
                  backgroundImage: u['avatar'] != null ? NetworkImage(avatarUrl('${u['id']}', '${u['avatar']}')) : null,
                  child: u['avatar'] == null ? Text('${(u['username'] ?? '?').toString().substring(0, 1)}') : null),
              title: Text('${u['username'] ?? '?'}'),
              trailing: IconButton(
                  icon: const Icon(Icons.message),
                  tooltip: 'Open DM (Ripcord: start DM)',
                  onPressed: () async {
                    final dm = await s.rest.openDm('${u['id']}');
                    await s.reloadAll();
                    onOpenDm({'id': '${dm['id']}', 'name': '${u['username']}', 'type': 1}, '');
                  }),
            );
          }),
        if (pending.isNotEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('PENDING REQUESTS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
        for (final f in pending)
          Builder(builder: (_) {
            final u = (f as Map)['user'] as Map? ?? {};
            return ListTile(
                leading: const Icon(Icons.person_add),
                title: Text('${u['username'] ?? '?'}'),
                subtitle: Text((f as Map)['type'] == 2 ? 'Incoming request' : 'Outgoing request'));
          }),
      ],
    );
  }
}
