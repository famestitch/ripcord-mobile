/// Discord Gateway (chat/guild events) + Voice Gateway (join handshake).
/// Auto-reconnect ke saath — disconnect par khud wapas judta hai.
library;

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class DiscordGateway {
  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  final void Function(Map<String, dynamic> event) onEvent;
  final void Function(String status)? onStatus; // connected | connecting | reconnecting | offline
  String? _token;
  int? _seq;
  Timer? _hb;
  bool _closed = false;
  int _backoff = 2;

  DiscordGateway({required this.onEvent, this.onStatus});

  void connect(String token) {
    _token = token;
    _closed = false;
    _backoff = 2;
    _connect();
  }

  void _connect() {
    if (_closed || _token == null) return;
    _hb?.cancel();
    try {
      _sub?.cancel();
    } catch (_) {}
    try {
      _ws?.sink.close();
    } catch (_) {}
    onStatus?.call('connecting');
    try {
      _ws = WebSocketChannel.connect(Uri.parse('wss://gateway.discord.gg/?v=9&encoding=json'));
    } catch (_) {
      _schedule();
      return;
    }
    _sub = _ws!.stream.listen(_onData, onError: (_) => _schedule(), onDone: () => _schedule(), cancelOnError: true);
  }

  void _onData(dynamic raw) {
    late Map<String, dynamic> m;
    try {
      m = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (m['s'] != null) _seq = m['s'] as int;
    switch (m['op']) {
      case 10: // HELLO
        final interval = (m['d']['heartbeat_interval'] as num).toInt();
        _hb?.cancel();
        _hb = Timer.periodic(Duration(milliseconds: interval), (_) {
          try {
            _ws?.sink.add(jsonEncode({'op': 1, 'd': _seq}));
          } catch (_) {
            _schedule();
          }
        });
        try {
          _ws?.sink.add(jsonEncode({
            'op': 2,
            'd': {
              'token': _token,
              'properties': {'os': 'android', 'browser': 'ripcord-mobile', 'device': 'ripcord-mobile'},
              'compress': false
            }
          }));
        } catch (_) {
          _schedule();
          return;
        }
        _backoff = 2;
        onStatus?.call('connected');
        break;
      case 11: // HEARTBEAT ACK — ignore
        break;
      case 0: // DISPATCH
        onEvent({'t': m['t'], 'd': m['d']});
        break;
      case 7: // RECONNECT requested
        _connect();
        break;
      case 9: // INVALID SESSION
        Future.delayed(const Duration(seconds: 3), _connect);
        break;
    }
  }

  void _schedule() {
    if (_closed) return;
    onStatus?.call('reconnecting');
    _hb?.cancel();
    Timer(Duration(seconds: _backoff), () {
      if (!_closed) _connect();
    });
    _backoff = (_backoff * 2).clamp(2, 60);
  }

  /// Voice channel join request — iske baad VOICE_SERVER_UPDATE + VOICE_STATE_UPDATE
  /// events aayenge, jinhe VoiceEngine ko dena hai.
  void joinVoice(String guildId, String channelId) {
    try {
      _ws?.sink.add(jsonEncode({
        'op': 4,
        'd': {'guild_id': guildId, 'channel_id': channelId, 'self_mute': false, 'self_deaf': false}
      }));
    } catch (_) {}
  }

  void leaveVoice(String guildId) {
    try {
      _ws?.sink.add(jsonEncode({
        'op': 4,
        'd': {'guild_id': guildId, 'channel_id': null, 'self_mute': false, 'self_deaf': false}
      }));
    } catch (_) {}
  }

  void close() {
    _closed = true;
    _hb?.cancel();
    try {
      _sub?.cancel();
    } catch (_) {}
    try {
      _ws?.sink.close();
    } catch (_) {}
    onStatus?.call('offline');
  }
}
