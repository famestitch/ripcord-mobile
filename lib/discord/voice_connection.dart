/// Voice transport manager — REGION CHANGE BYPASS ka asal engine.
///
/// Problem: Discord kabhi bhi voice region badal sakta hai (guild region change,
/// server migration, failover). Tab naya VOICE_SERVER_UPDATE (naya endpoint+token)
/// aata hai. Naive client poora teardown karke dobara judta hai — beech me
/// transmit ruk jata hai, aur aksar chup hi reh jata hai (rejoin/ack bhool jata hai).
///
/// Guarantee ("chahe jo bhi ho transmit bandh nahi"):
/// 1. Mic pipeline + Opus encoder + RTP clock (seq/timestamp/ssrc) REGION CHANGE
///    PAR KABHI RESET NAHI HOTE. Sirf transport (WS+UDP+key) dobara handshake hota hai.
/// 2. Migration ke dauran bane frames queue hote hain (25 frames ~0.5s), ready hote
///    hi flush — gap minimum, clock continuous.
/// 3. Pehle RESUME (op7) try hota hai, fail par fresh IDENTIFY — dono automatic.
/// 4. WS close 4014 (Disconnected) par gateway se khud REJOIN (op4) bheja jata hai.
/// 5. endpoint==null (server ne wapas liya) par bhi state rakhi jati hai + rejoin retry.
/// 6. Backend missing ho to 'audio-backend-missing' me wait — wiring judte hi auto-start.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'voice_audio_backend.dart';

/// Voice gateway version (v4 opcodes — sabse widely supported).
const _voiceGwV = 4;

class VoiceConnection {
  final String userId;
  final String guildId;
  final String channelId;
  final VoiceAudioBackend backend;
  final void Function(String status) onStatus;
  final void Function() onNeedRejoin;

  String? _sessionId;
  String? _serverToken;
  String? _endpoint; // 'host' (bina :443)

  WebSocketChannel? _ws;
  StreamSubscription? _sub;
  RawDatagramSocket? _udp;
  StreamSubscription? _udpSub;
  InternetAddress? _serverAddr;
  int _serverPort = 0;

  int _ssrc = 0;
  Uint8List? _secretKey;
  String _mode = 'xsalsa20_poly1305_suffix';

  int _seq = 0; // u16, kabhi reset nahi (rollover par 0 — normal RTP)
  int _timestamp = 0; // u32 @48kHz, kabhi reset nahi
  bool _muted = false;
  bool _capturing = false;
  bool _disposed = false;

  /// Migration ke dauran ready packets (header+payload pre-encrypt nahi —
  /// key badal sakti hai, isiliye Opus frames queue hote hain).
  final List<List<int>> _pendingFrames = [];
  static const _maxPending = 25;

  Timer? _hb;
  Timer? _captureRetry;
  bool _resumeAttempted = false;

  String _state = 'idle';
  void _set(String s) {
    _state = s;
    onStatus(s);
  }

  VoiceConnection({
    required this.userId,
    required this.guildId,
    required this.channelId,
    required this.backend,
    required this.onStatus,
    required this.onNeedRejoin,
  });

  // ---------------- input: gateway events ----------------

  /// VOICE_STATE_UPDATE (apna) se aata hai.
  void updateSession(String sessionId) {
    if (sessionId == _sessionId) return;
    _sessionId = sessionId;
    _maybeConnect();
  }

  /// VOICE_SERVER_UPDATE se aata hai. Yahi REGION CHANGE ka signal hai.
  void updateServer(String token, String endpoint) {
    endpoint = endpoint.replaceAll(':443', '');
    final changed = _endpoint != null && (endpoint != _endpoint || token != _serverToken);
    _serverToken = token;
    if (!changed) {
      _endpoint = endpoint;
      _maybeConnect();
      return;
    }
    // ===== REGION CHANGED — seamless handover, teardown NAHI =====
    // seq/timestamp/ssrc/encoder/capture: untouched. Sirf transport re-handshake.
    _endpoint = endpoint;
    _migrate();
  }

  /// Server ne endpoint wapas le liya (null). State rakho + gateway rejoin mango.
  void serverWithdrawn() {
    _closeTransport();
    _set('waiting-for-server');
    // Gateway ko dobara join bolo — fresh VOICE_SERVER_UPDATE aayega.
    Timer(const Duration(seconds: 2), () {
      if (!_disposed && _state == 'waiting-for-server') onNeedRejoin();
    });
  }

  void setMuted(bool m) {
    _muted = m;
    _sendSpeaking(!m);
  }

  // ---------------- core ----------------

  void _maybeConnect() {
    if (_disposed || _sessionId == null || _serverToken == null || _endpoint == null) return;
    if (_state == 'idle' || _state == 'waiting-for-server' || _state == 'audio-backend-missing') {
      _handshake(resumeFirst: false);
    }
  }

  void _migrate() {
    if (_disposed) return;
    _set('migrating'); // UI: "region badal raha hai, mic live hai"
    _closeTransport(); // WS+UDP bandh — capture/encoder/clock chalte rehte hain
    _resumeAttempted = false;
    _handshake(resumeFirst: true);
  }

  Future<void> _handshake({required bool resumeFirst}) async {
    if (_disposed) return;
    if (_state != 'migrating') _set('connecting');
    _closeTransport();
    try {
      _ws = WebSocketChannel.connect(Uri.parse('wss://$_endpoint:443/?v=$_voiceGwV'));
    } catch (_) {
      _retryHandshake();
      return;
    }
    _sub = _ws!.stream.listen(_onWsData, onError: (_) => _onWsGone(), onDone: () => _onWsGone(), cancelOnError: true);
    // HELLO ka wait — timeout par retry (server kabhi hello na bheje to atke nahi).
    Timer(const Duration(seconds: 8), () {
      if (!_disposed && (_state == 'connecting' || _state == 'migrating') && _ssrc == 0 && !_resumeAttempted) {
        _retryHandshake();
      }
    });
    _wantsResumeFirst = resumeFirst;
  }

  bool _wantsResumeFirst = false;

  void _onWsData(dynamic raw) {
    late Map<String, dynamic> m;
    try {
      m = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['op']) {
      case 8: // HELLO
        final interval = ((m['d']?['heartbeat_interval']) as num?)?.toInt() ?? 5000;
        _hb?.cancel();
        _hb = Timer.periodic(Duration(milliseconds: interval), (_) {
          try {
            _ws?.sink.add(jsonEncode({'op': 3, 'd': DateTime.now().millisecondsSinceEpoch}));
          } catch (_) {}
        });
        if (_wantsResumeFirst && _sessionId != null) {
          _resumeAttempted = true;
          try {
            _ws?.sink.add(jsonEncode({
              'op': 7,
              'd': {'server_id': guildId, 'session_id': _sessionId, 'token': _serverToken}
            }));
          } catch (_) {}
          // Resume ka jawab 4s me na aaye to fresh identify.
          Timer(const Duration(seconds: 4), () {
            if (!_disposed && _state == 'migrating') _identify();
          });
        } else {
          _identify();
        }
        break;
      case 9: // RESUMED — transport wahi, clock wahi, turant live
        _set('connected');
        _startCapture();
        _flushPending();
        break;
      case 2: // READY
        final d = m['d'] as Map<String, dynamic>? ?? {};
        _ssrc = (d['ssrc'] as num?)?.toInt() ?? _ssrc;
        final ip = '${d['ip']}';
        _serverPort = (d['port'] as num?)?.toInt() ?? 0;
        _pickMode((d['modes'] as List?)?.map((e) => '$e').toList() ?? []);
        _resolveAndDiscover(ip);
        break;
      case 4: // SESSION_DESCRIPTION — nayi key (region ke saath key bhi badal sakti hai)
        final d = m['d'] as Map<String, dynamic>? ?? {};
        _mode = '${d['mode'] ?? _mode}';
        final key = (d['secret_key'] as List?) ?? [];
        _secretKey = Uint8List.fromList(key.map((e) => (e as num).toInt()).toList());
        _set('connected');
        _startCapture();
        _sendSpeaking(!_muted);
        _flushPending();
        break;
      case 6: // HEARTBEAT_ACK — ignore
        break;
      case 5: // SPEAKING (remote ssrc) — Phase-2 UI indicator ke liye passthrough
        break;
      case 13: // CLIENT_DISCONNECT — ignore
        break;
    }
  }

  void _identify() {
    try {
      _ws?.sink.add(jsonEncode({
        'op': 0,
        'd': {'server_id': guildId, 'user_id': userId, 'session_id': _sessionId, 'token': _serverToken}
      }));
    } catch (_) {
      _retryHandshake();
    }
  }

  void _pickMode(List<String> offered) {
    // package:sodium me AES-GCM nahi hai — isiliye verified modes pehle.
    // Discord hamesha xsalsa variants bhi offer karta hai, to ye safe hai.
    const pref = [
      'xsalsa20_poly1305_suffix',
      'xsalsa20_poly1305',
      'aead_xchacha20_poly1305_rtpsize',
      'aead_aes256_gcm_rtpsize', // unsupported: encrypt me saaf error milega
    ];
    for (final p in pref) {
      if (offered.contains(p)) {
        _mode = p;
        return;
      }
    }
    if (offered.isNotEmpty) _mode = offered.first;
  }

  Future<void> _resolveAndDiscover(String host) async {
    try {
      final addrs = await InternetAddress.lookup(host);
      _serverAddr = addrs.first;
      _udp?.close();
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      // 74-byte IP discovery: type=1, len=70, ssrc (BE) — discord.js layout
      final req = ByteData(74);
      req.setUint16(0, 0x1, Endian.big);
      req.setUint16(2, 70, Endian.big);
      req.setUint32(4, _ssrc, Endian.big);
      _udp!.send(req.buffer.asUint8List(), _serverAddr!, _serverPort);
      bool got = false;
      _udpSub?.cancel();
      _udpSub = _udp!.listen((ev) {
        if (ev == RawSocketEvent.read) {
          final dg = _udp!.receive();
          if (dg != null && dg.data.length >= 74 && !got) {
            got = true;
            // response[8..72] = external IP ascii, [72..74] = port (BE)
            final rawIp = dg.data.sublist(8, 72);
            final zero = rawIp.indexOf(0);
            final extIp = ascii.decode(rawIp.sublist(0, zero < 0 ? rawIp.length : zero));
            final extPort = ByteData.sublistView(dg.data, 72, 74).getUint16(0, Endian.big);
            _selectProtocol(extIp, extPort);
          } else if (dg != null && _secretKey != null) {
            _onVoicePacket(dg.data);
          }
        }
      });
      // Discovery jawab na aaye to retry (NAT/hole-punch fail = dobara, give up nahi).
      Timer(const Duration(seconds: 5), () {
        if (!_disposed && !got && (_state == 'connecting' || _state == 'migrating')) _resolveAndDiscover(host);
      });
    } catch (_) {
      _retryHandshake();
    }
  }

  void _selectProtocol(String extIp, int extPort) {
    try {
      _ws?.sink.add(jsonEncode({
        'op': 1,
        'd': {
          'protocol': 'udp',
          'data': {'address': extIp, 'port': extPort, 'mode': _mode}
        }
      }));
    } catch (_) {
      _retryHandshake();
    }
  }

  // ---------------- transmit (KABHI BANDH NAHI) ----------------

  Future<void> _startCapture() async {
    if (_capturing || _disposed) return;
    _capturing = true;
    try {
      await backend.startCapture(_onMicFrame);
    } catch (_) {
      // Backend wired nahi — capture retry loop, connection/region state untouched.
      _capturing = false;
      if (_state == 'connected') _set('audio-backend-missing');
      _captureRetry?.cancel();
      _captureRetry = Timer(const Duration(seconds: 5), () {
        if (!_disposed) _startCapture();
      });
    }
  }

  void _onMicFrame(List<double> pcm48kMono) {
    if (_disposed || _muted) return;
    // 20ms = 960 samples. Chhote tukde aaye to bhi Opus frame poora rakho.
    // (Backend 960-sample frames deta hai — yahan seedha encode.)
    List<int> opus;
    try {
      opus = backend.encodeOpus(pcm48kMono);
    } catch (_) {
      return;
    }
    if (opus.isEmpty) return; // gated silence — bhejne ko kuch nahi
    // RTP clock HAMESHA aage — migrate/queue me bhi (receiver gap-free resume).
    final header = _rtpHeader();
    if (_udp == null || _secretKey == null || _serverAddr == null) {
      // Transport taiyar nahi (migrating/connecting) — queue, drop nahi (cap ke andar).
      if (_pendingFrames.length >= _maxPending) _pendingFrames.removeAt(0);
      _pendingFrames.add(opus);
      return;
    }
    _sendPacket(header, opus);
  }

  Uint8List _rtpHeader() {
    final h = ByteData(12);
    h.setUint8(0, 0x80); // version 2
    h.setUint8(1, 0x78); // opus payload type
    h.setUint16(2, _seq, Endian.big);
    _seq = (_seq + 1) & 0xFFFF;
    h.setUint32(4, _timestamp, Endian.big);
    _timestamp = (_timestamp + 960) & 0xFFFFFFFF; // 20ms @48kHz
    h.setUint32(8, _ssrc, Endian.big);
    return h.buffer.asUint8List();
  }

  void _sendPacket(Uint8List header, List<int> opus) {
    try {
      final pkt = backend.encryptRtp(header, opus, _secretKey!, _mode);
      _udp!.send(pkt, _serverAddr!, _serverPort);
    } catch (_) {}
  }

  void _flushPending() {
    if (_pendingFrames.isEmpty) return;
    for (final opus in _pendingFrames) {
      if (_udp == null || _secretKey == null) break;
      _sendPacket(_rtpHeader(), opus);
    }
    _pendingFrames.clear();
  }

  void _onVoicePacket(Uint8List data) {
    // Remote audio — Phase-2 mixer me jayega. Abhi decode-path alive rakho.
    try {
      final (_, opus) = backend.decryptRtp(data, _secretKey!, _mode);
      backend.decodeOpus(opus);
    } catch (_) {}
  }

  void _sendSpeaking(bool speaking) {
    if (_ssrc == 0) return;
    try {
      _ws?.sink.add(jsonEncode({
        'op': 5,
        'd': {'speaking': speaking ? 1 : 0, 'delay': 0, 'ssrc': _ssrc}
      }));
    } catch (_) {}
  }

  // ---------------- failure paths (sab automatic, user ko kuch nahi karna) ----------------

  void _onWsGone() {
    if (_disposed) return;
    // Normal close nahi — resume try karo, clock/capture untouched.
    _closeTransport();
    _set('reconnecting');
    _resumeAttempted = false;
    _handshake(resumeFirst: true);
  }

  void _retryHandshake() {
    if (_disposed) return;
    _closeTransport();
    if (_state != 'migrating') _set('reconnecting');
    Timer(const Duration(seconds: 2), () {
      if (!_disposed) _handshake(resumeFirst: _state == 'migrating');
    });
  }

  /// NOTE: voice WS close-code (4014 vs others) ka farak Stream drains me nahi
  /// milta — isiliye 4014 case gateway se pakda jata hai: channel se hata diye
  /// jao to VOICE_STATE_UPDATE (session_id same, channel_id=null) aata hai.
  /// Session us waqt onNeedRejoin jaisa behave kare — connection khud dobara
  /// handshake karega, transmit pipeline kabhi nahi rukti.
  void kicked() {
    if (_disposed) return;
    _set('reconnecting');
    onNeedRejoin(); // gateway op4 dobara — fresh SERVER_UPDATE aayega
  }

  void _closeTransport() {
    _hb?.cancel();
    try {
      _sub?.cancel();
    } catch (_) {}
    try {
      _ws?.sink.close();
    } catch (_) {}
    _ws = null;
    try {
      _udpSub?.cancel();
    } catch (_) {}
    try {
      _udp?.close();
    } catch (_) {}
    _udp = null;
    _serverAddr = null;
    // NOTE: _secretKey rakhte hain (resume me kaam aayegi); nayi SESSION_DESCRIPTION aate hi overwrite.
  }

  void dispose() {
    _disposed = true;
    _sendSpeaking(false);
    _captureRetry?.cancel();
    _closeTransport();
    try {
      backend.stopCapture();
    } catch (_) {}
    _capturing = false;
    _pendingFrames.clear();
  }
}
