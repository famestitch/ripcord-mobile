/// Shared session state — Ripcord ke "Accounts + tabs + sidebar + voice" ka phone equivalent.
/// Ek hi Gateway/REST yahan rehta hai, saari screens AnimatedBuilder se sunti hain.
library;

import 'package:flutter/foundation.dart';
import 'discord/rest.dart';
import 'discord/gateway.dart';
import 'discord/voice_connection.dart';
import 'discord/voice_audio_backend.dart';
import 'discord/loudmic_backend.dart';

class Session extends ChangeNotifier {
  DiscordRest rest;
  late DiscordGateway gw;
  Map<String, dynamic> me;

  List<dynamic> guilds = [];
  List<dynamic> dms = [];
  List<dynamic> friends = [];
  String? guildId; // null = DM view
  List<dynamic> channels = [];
  List<dynamic> members = [];
  List<dynamic> roles = [];
  Map<String, List<dynamic>> messagesByChannel = {};
  Map<String, Set<String>> typingByChannel = {}; // channelId -> usernames
  List<Map<String, dynamic>> mentions = [];
  List<Map<String, String>> bookmarks = []; // {guildId/channelId, name}
  Map<String, int> unreadByChannel = {}; // client-side unread (gateway se)
  String? openChannelId; // abhi khula channel — uska unread nahi badhega
  final Set<String> loadingOlder = {};
  String gatewayStatus = 'offline';
  DateTime? _lastTypingSent;

  /// guildId -> userId -> voice state {channel_id, self_mute, self_deaf, mute, deaf}
  Map<String, Map<String, dynamic>> voiceStates = {};
  Map<String, dynamic>? voiceServer;
  String? voiceSessionId;
  String? voiceGuildId;
  String? voiceChannelId;
  bool voiceMuted = false;
  bool voiceDeafened = false;
  double micGainDb = 0.0;

  /// Voice transport (region-bypass engine). Native backend judte hi media live.
  VoiceConnection? voiceConn;
  String voiceStatus = 'idle';
  VoiceAudioBackend audioBackend = LoudMicBackend();

  /// LOUDMIC settings — VoiceScreen sliders yahin likhte hain.
  double gateThreshold = 0.15;
  bool musicMode = false;

  /// UI change → backend. Har slider change ke baad call karo.
  void syncAudioToBackend() {
    audioBackend.gainDb = micGainDb;
    audioBackend.gateThreshold = gateThreshold;
    audioBackend.setMusicMode(musicMode);
    notifyListeners();
  }

  Session({required String token, required this.me}) : rest = DiscordRest(token) {
    gw = DiscordGateway(onEvent: _onEvent, onStatus: (st) {
      gatewayStatus = st;
      notifyListeners();
    });
    gw.connect(token);
    reloadAll();
  }

  String get myId => '${me['id']}';
  String get myName => '${me['username'] ?? 'me'}';

  Future<void> reloadAll() async {
    try {
      guilds = await rest.guilds();
      dms = await rest.dmChannels();
      friends = await rest.relationships();
      if (guilds.isNotEmpty && guildId == null) {
        await selectGuild((guilds.first as Map)['id'] as String);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> selectGuild(String id) async {
    guildId = id;
    channels = [];
    notifyListeners();
    try {
      final c = await rest.channels(id);
      c.sort((a, b) => ((a['position'] ?? 0) as int).compareTo((b['position'] ?? 0) as int));
      channels = c;
      notifyListeners();
      members = await rest.guildMembers(id);
      roles = await rest.roles(id);
      notifyListeners();
    } catch (_) {}
  }

  List<dynamic> get textChannels =>
      channels.where((c) => (c['type'] ?? 0) == 0 || (c['type'] ?? 0) == 5).toList();
  List<dynamic> get voiceChannels => channels.where((c) => (c['type'] ?? 0) == 2).toList();

  /// Category groups (Ripcord tree: category -> channels), uncategorized last me.
  Map<String?, List<dynamic>> get groupedText {
    final map = <String?, List<dynamic>>{};
    for (final c in textChannels) {
      final m = c as Map<String, dynamic>;
      final cat = m['parent_id'] as String?;
      map.putIfAbsent(cat, () => []).add(m);
    }
    return map;
  }

  String categoryName(String? catId) {
    if (catId == null) return 'TEXT CHANNELS';
    for (final c in channels) {
      final m = c as Map<String, dynamic>;
      if ('${m['id']}' == catId) return ('${m['name'] ?? 'category'}').toUpperCase();
    }
    return 'TEXT CHANNELS';
  }

  Future<void> openChannel(String id) async {
    openChannelId = id;
    unreadByChannel.remove(id);
    notifyListeners();
    try {
      final m = await rest.messages(id);
      messagesByChannel[id] = m;
      notifyListeners();
      // Ripcord read-state sync: newest message tak read mark karo
      if (m.isNotEmpty) {
        try {
          await rest.ack(id, '${(m.first as Map)['id']}');
        } catch (_) {}
      }
    } catch (_) {}
  }

  void closeChannel() {
    openChannelId = null;
  }

  /// Ripcord infinite scroll: upar scroll par purane messages lao.
  Future<void> loadOlder(String channelId) async {
    final list = messagesByChannel[channelId];
    if (list == null || list.isEmpty || loadingOlder.contains(channelId)) return;
    loadingOlder.add(channelId);
    notifyListeners();
    try {
      final oldest = '${(list.last as Map)['id']}';
      final older = await rest.messages(channelId, before: oldest);
      final ids = list.map((m) => '${(m as Map)['id']}').toSet();
      for (final m in older) {
        if (!ids.contains('${(m as Map)['id']}')) list.add(m);
      }
    } catch (_) {
    } finally {
      loadingOlder.remove(channelId);
      notifyListeners();
    }
  }

  /// Typing indicator — har keystroke par POST nahi (rate-limit lagega).
  /// Max 1 typing event per 8 sec, fire-and-forget.
  void noteTyping(String channelId) {
    final now = DateTime.now();
    if (_lastTypingSent != null && now.difference(_lastTypingSent!).inSeconds < 8) return;
    _lastTypingSent = now;
    rest.typing(channelId);
  }

  /// Send — fail par throw karta hai taaki UI error dikhaye.
  /// Gateway echo se duplicate na aaye, isiliye id check hai.
  Future<Map<String, dynamic>> send(String channelId, String text) async {
    final t = text.trim();
    if (t.isEmpty) throw Exception('empty message');
    final m = await rest.sendMessage(channelId, t);
    final list = messagesByChannel.putIfAbsent(channelId, () => []);
    if (!list.any((x) => '${(x as Map)['id']}' == '${m['id']}')) list.insert(0, m);
    notifyListeners();
    return m;
  }

  bool isBookmarked(String channelId) => bookmarks.any((b) => b['channelId'] == channelId);
  void toggleBookmark(String guildId, String channelId, String name) {
    if (isBookmarked(channelId)) {
      bookmarks.removeWhere((b) => b['channelId'] == channelId);
    } else {
      bookmarks.add({'guildId': guildId, 'channelId': channelId, 'name': name});
    }
    notifyListeners();
  }

  void _onEvent(Map<String, dynamic> e) {
    final t = e['t'] as String?;
    final d = e['d'];
    if (d is! Map<String, dynamic>) return;
    switch (t) {
      case 'MESSAGE_CREATE':
        final chId = '${d['channel_id']}';
        final mid = '${d['id']}';
        final list = messagesByChannel[chId];
        if (list != null) {
          // Apne bheje msg ka gateway echo duplicate na bane
          if (!list.any((x) => '${(x as Map)['id']}' == mid)) {
            list.insert(0, d);
            if (list.length > 200) list.removeRange(200, list.length);
          }
          try {
            rest.ack(chId, mid);
          } catch (_) {}
        }
        if (chId != openChannelId) {
          unreadByChannel[chId] = (unreadByChannel[chId] ?? 0) + 1;
        }
        final content = '${d['content'] ?? ''}';
        final mentioned = (d['mentions'] as List?)?.any((u) => '${(u as Map)['id']}' == myId) ?? false;
        if (mentioned || content.contains('@$myName')) {
          mentions.insert(0, {'channel_id': chId, 'guild_id': '${d['guild_id'] ?? ''}', 'msg': d});
          if (mentions.length > 200) mentions.removeLast();
        }
        notifyListeners();
        break;
      case 'TYPING_START':
        final chId = '${d['channel_id']}';
        final u = (d['member']?['nick'] ?? d['user']?['username'] ?? 'someone').toString();
        if ('${d['user_id']}' != myId) {
          typingByChannel.putIfAbsent(chId, () => {}).add(u);
          notifyListeners();
          Future.delayed(const Duration(seconds: 6), () {
            typingByChannel[chId]?.remove(u);
            notifyListeners();
          });
        }
        break;
      case 'VOICE_STATE_UPDATE':
        final g = '${d['guild_id'] ?? ''}';
        final u = '${d['user_id']}';
        voiceStates.putIfAbsent(g, () => {})[u] = d;
        if (u == myId) {
          voiceSessionId = d['session_id'] as String?;
          // Channel se nikala gaya (4014 jaisa) to connection khud rejoin mangegi.
          if (d['channel_id'] == null && voiceConn != null && g == (voiceGuildId ?? '')) {
            voiceConn!.kicked();
          } else if (voiceSessionId != null && voiceConn != null && g == (voiceGuildId ?? '')) {
            voiceConn!.updateSession(voiceSessionId!);
          }
        }
        notifyListeners();
        break;
      case 'VOICE_SERVER_UPDATE':
        voiceServer = d;
        // Yahi region-change signal hai — connection ko forward (bypass engine sambhalega).
        if (voiceConn != null && '${d['guild_id']}' == (voiceGuildId ?? '')) {
          if (d['endpoint'] == null) {
            voiceConn!.serverWithdrawn();
          } else {
            voiceConn!.updateServer('${d['token']}', '${d['endpoint']}');
          }
        }
        notifyListeners();
        break;
      case 'GUILD_CREATE':
        // Initial members + presences bulk me aate hain — member list yahin se bharti hai.
        final g = '${d['id']}';
        if (g == guildId && d['members'] is List) {
          members = d['members'] as List<dynamic>;
          notifyListeners();
        }
        break;
      case 'PRESENCE_UPDATE':
      case 'GUILD_MEMBER_ADD':
      case 'GUILD_MEMBER_REMOVE':
        if ('${d['guild_id']}' == guildId) selectGuild(guildId!);
        break;
    }
  }

  void joinVoice(String gId, String chId) {
    voiceGuildId = gId;
    voiceChannelId = chId;
    voiceConn?.dispose();
    voiceConn = VoiceConnection(
      userId: myId,
      guildId: gId,
      channelId: chId,
      backend: audioBackend,
      onStatus: (st) {
        voiceStatus = st;
        notifyListeners();
      },
      onNeedRejoin: () {
        if (voiceGuildId != null && voiceChannelId != null) gw.joinVoice(voiceGuildId!, voiceChannelId!);
      },
    );
    // Race: SERVER/STATE updates jo join se pehle aa chuke hon (same guild ke hon to do).
    if (voiceSessionId != null) voiceConn!.updateSession(voiceSessionId!);
    if (voiceServer != null && '${voiceServer!['guild_id']}' == gId && voiceServer!['endpoint'] != null) {
      voiceConn!.updateServer('${voiceServer!['token']}', '${voiceServer!['endpoint']}');
    }
    voiceStatus = 'joining';
    syncAudioToBackend();
    gw.joinVoice(gId, chId);
    notifyListeners();
  }

  void leaveVoice() {
    voiceConn?.dispose();
    voiceConn = null;
    voiceStatus = 'idle';
    if (voiceGuildId != null) gw.leaveVoice(voiceGuildId!);
    voiceGuildId = null;
    voiceChannelId = null;
    voiceServer = null;
    notifyListeners();
  }

  void toggleVoiceMute() {
    voiceMuted = !voiceMuted;
    voiceConn?.setMuted(voiceMuted);
    notifyListeners();
  }

  /// channelId -> connected users (Ripcord: voice channel ke andar inline users)
  List<Map<String, dynamic>> voiceUsersIn(String gId, String chId) {
    final out = <Map<String, dynamic>>[];
    final states = voiceStates[gId];
    if (states == null) return out;
    states.forEach((uid, st) {
      if ('${st['channel_id']}' == chId) out.add({'user_id': uid, ...st});
    });
    return out;
  }

  String displayName(String userId) {
    for (final m in members) {
      final mm = m as Map<String, dynamic>;
      final u = mm['user'] as Map<String, dynamic>?;
      if (u != null && '${u['id']}' == userId) {
        return '${mm['nick'] ?? u['username'] ?? userId}';
      }
    }
    for (final r in friends) {
      final u = (r as Map)['user'] as Map?;
      if (u != null && '${u['id']}' == userId) return '${u['username']}';
    }
    if (userId == myId) return myName;
    return 'user-$userId';
  }

  @override
  void dispose() {
    gw.close();
    super.dispose();
  }
}
