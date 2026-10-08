/// Discord REST (user client). WARNING: 3rd-party user-client ToS ke against —
/// pehle alt/test account se try karo.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

class DiscordRest {
  static const api = 'https://discord.com/api/v9';
  final String token;
  DiscordRest(this.token);

  Map<String, String> get _h => {
        'Authorization': token,
        'Content-Type': 'application/json',
        'User-Agent': 'RipcordMobile/0.1.0',
      };

  /// Token login verify: GET /users/@me
  Future<Map<String, dynamic>> me() async {
    final r = await http.get(Uri.parse('$api/users/@me'), headers: _h);
    if (r.statusCode != 200) throw Exception('auth failed: ${r.statusCode} ${r.body}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> guilds() async {
    final r = await http.get(Uri.parse('$api/users/@me/guilds'), headers: _h);
    if (r.statusCode != 200) throw Exception('guilds: ${r.statusCode}');
    return jsonDecode(r.body) as List<dynamic>;
  }

  Future<List<dynamic>> channels(String guildId) async {
    final r = await http.get(Uri.parse('$api/guilds/$guildId/channels'), headers: _h);
    if (r.statusCode != 200) throw Exception('channels: ${r.statusCode}');
    return jsonDecode(r.body) as List<dynamic>;
  }

  Future<List<dynamic>> messages(String channelId, {int limit = 50, String? before}) async {
    var url = '$api/channels/$channelId/messages?limit=$limit';
    if (before != null) url += '&before=$before';
    final r = await http.get(Uri.parse(url), headers: _h);
    if (r.statusCode != 200) throw Exception('messages: ${r.statusCode}');
    return jsonDecode(r.body) as List<dynamic>;
  }

  /// Ripcord: send on Enter. Rate-limit (429) par retry_after follow karo.
  Future<Map<String, dynamic>> sendMessage(String channelId, String content) async {
    final r = await http.post(Uri.parse('$api/channels/$channelId/messages'),
        headers: _h, body: jsonEncode({'content': content}));
    if (r.statusCode == 429) throw Exception('rate-limited — thoda rukke bhejo');
    if (r.statusCode != 200) throw Exception('send: ${r.statusCode} ${r.body}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> editMessage(String channelId, String msgId, String content) async {
    final r = await http.patch(Uri.parse('$api/channels/$channelId/messages/$msgId'),
        headers: _h, body: jsonEncode({'content': content}));
    if (r.statusCode != 200) throw Exception('edit: ${r.statusCode}');
  }

  Future<void> deleteMessage(String channelId, String msgId) async {
    final r = await http.delete(Uri.parse('$api/channels/$channelId/messages/$msgId'), headers: _h);
    if (r.statusCode != 204 && r.statusCode != 200) throw Exception('delete: ${r.statusCode}');
  }

  Future<void> typing(String channelId) async {
    await http.post(Uri.parse('$api/channels/$channelId/typing'), headers: _h);
  }

  Future<void> ack(String channelId, String msgId) async {
    await http.post(Uri.parse('$api/channels/$channelId/messages/$msgId/ack'), headers: _h, body: jsonEncode({}));
  }

  Future<List<dynamic>> pins(String channelId) async {
    final r = await http.get(Uri.parse('$api/channels/$channelId/pins'), headers: _h);
    if (r.statusCode != 200) throw Exception('pins: ${r.statusCode}');
    return jsonDecode(r.body) as List<dynamic>;
  }

  /// Ripcord right member panel. (Bade servers par limit/after paging lagao.)
  Future<List<dynamic>> guildMembers(String guildId, {int limit = 100}) async {
    final r = await http.get(Uri.parse('$api/guilds/$guildId/members?limit=$limit'), headers: _h);
    if (r.statusCode != 200) throw Exception('members: ${r.statusCode}');
    return jsonDecode(r.body) as List<dynamic>;
  }

  Future<List<dynamic>> roles(String guildId) async {
    final r = await http.get(Uri.parse('$api/guilds/$guildId/roles'), headers: _h);
    if (r.statusCode != 200) throw Exception('roles: ${r.statusCode}');
    return jsonDecode(r.body) as List<dynamic>;
  }

  /// Friends tab + DM open/close (Ripcord: start/go DM via context menu)
  Future<List<dynamic>> relationships() async {
    final r = await http.get(Uri.parse('$api/users/@me/relationships'), headers: _h);
    if (r.statusCode != 200) throw Exception('friends: ${r.statusCode}');
    return jsonDecode(r.body) as List<dynamic>;
  }

  Future<List<dynamic>> dmChannels() async {
    final r = await http.get(Uri.parse('$api/users/@me/channels'), headers: _h);
    if (r.statusCode != 200) throw Exception('dms: ${r.statusCode}');
    return jsonDecode(r.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> openDm(String userId) async {
    final r = await http.post(Uri.parse('$api/users/@me/channels'),
        headers: _h, body: jsonEncode({'recipient_id': userId}));
    if (r.statusCode != 200) throw Exception('openDm: ${r.statusCode} ${r.body}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Email+pass reference — asal me captcha (hCaptcha) + MFA lagega.
  /// Sirf samajhne ke liye rakha hai; production me token/QR use karo.
  static Future<String> loginWithPassword(String email, String password) async {
    final r = await http.post(
      Uri.parse('$api/auth/login'),
      headers: {'Content-Type': 'application/json', 'User-Agent': 'RipcordMobile/0.1.0'},
      body: jsonEncode({'login': email, 'password': password, 'undelete': false}),
    );
    if (r.statusCode == 400 && r.body.contains('captcha')) {
      throw Exception('hCaptcha required — browser me login karke token nikalo.');
    }
    if (r.statusCode != 200) throw Exception('login failed: ${r.statusCode} ${r.body}');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j.containsKey('mfa') && j['mfa'] == true) throw Exception('MFA code chahiye (totp).');
    return j['token'] as String;
  }
}
