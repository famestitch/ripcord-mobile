import 'package:flutter/material.dart';
import 'ui/login_screen.dart';
import 'ui/ripcord_theme.dart';

void main() => runApp(const RipcordMobile());

/// Ripcord Style page default: dark theme. Prefs yahin banta hai taaki
/// login screen bhi Ripcord look me dikhe.
class RipcordMobile extends StatefulWidget {
  const RipcordMobile({super.key});
  @override
  State<RipcordMobile> createState() => _RipcordMobileState();
}

class _RipcordMobileState extends State<RipcordMobile> {
  final _prefs = RipcordPrefs();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _prefs,
      builder: (_, __) => MaterialApp(
        title: 'Ripcord Mobile',
        theme: _prefs.theme,
        home: const LoginScreen(),
      ),
    );
  }
}
