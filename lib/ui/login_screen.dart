import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../discord/rest.dart';
import '../session.dart';
import 'ripcord_theme.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _store = const FlutterSecureStorage();
  final _tokenC = TextEditingController();
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  String? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tokenC.text = ''; // dev: apna test-alt token yahan paste karo
  }

  Future<void> _go(String token) async {
    setState(() { _busy = true; _err = null; });
    try {
      final me = await DiscordRest(token).me();
      await _store.write(key: 'discord_token', value: token);
      if (!mounted) return;
      final prefs = RipcordPrefs();
      final session = Session(token: token, me: me);
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => AnimatedBuilder(
                  animation: prefs,
                  builder: (_, __) => MaterialApp(
                      title: 'Ripcord Mobile',
                      theme: prefs.theme,
                      home: HomeScreen(session: session, prefs: prefs)))));
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ripcord Mobile — Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Note: 3rd-party login Discord ToS ke against hai. Pehle ALT/test account se try karo.',
                style: TextStyle(color: Colors.grey)),
            TabBar(controller: _tab, tabs: const [Tab(text: 'Token'), Tab(text: 'Email+Pass')]),
            Expanded(
              child: TabBarView(controller: _tab, children: [
                Column(children: [
                  TextField(controller: _tokenC, decoration: const InputDecoration(labelText: 'User token'), obscureText: true, maxLines: 1),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: _busy ? null : () => _go(_tokenC.text.trim()), child: const Text('Token se login')),
                ]),
                Column(children: [
                  TextField(controller: _emailC, decoration: const InputDecoration(labelText: 'Email')),
                  TextField(controller: _passC, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _busy ? null : () async {
                      setState(() { _busy = true; _err = null; });
                      try {
                        final t = await DiscordRest.loginWithPassword(_emailC.text.trim(), _passC.text);
                        await _go(t);
                      } catch (e) {
                        setState(() => _err = e.toString());
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
                    child: const Text('Email+Pass se login (captcha lag sakta hai)')),
                ]),
              ]),
            ),
            if (_err != null) Text(_err!, style: const TextStyle(color: Colors.grey)),
            if (_busy) const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
