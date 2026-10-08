/// Ripcord Style page — PURE BLACK & WHITE theme (koi rang nahi, koi emoji nahi).
/// dark = black bg + white icons/text | light = white bg + black icons/text.
/// Chat content (avatars, server icons, user emoji) ke original colors rehte hain —
/// sirf UI chrome monochrome hai.
library;

import 'package:flutter/material.dart';

class RipcordPrefs extends ChangeNotifier {
  bool dark = true;
  double chatFontSize = 14.0; // Ripcord: Chat Font
  double sidebarFontSize = 13.0; // Ripcord: sidebar font
  bool showAvatars = true; // Ripcord: Avatars in Chat
  double avatarSize = 36.0; // Ripcord: Chat avatar size
  bool showTimestamps = true; // Ripcord: Chat Timestamp
  bool compact = true; // tight rows (Ripcord default feel)

  void toggleTheme() {
    dark = !dark;
    notifyListeners();
  }

  ThemeData get theme {
    if (dark) {
      final base = ThemeData.dark(useMaterial3: true);
      return base.copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: Colors.white,
          onSecondary: Colors.black,
          surface: Colors.black,
          onSurface: Colors.white,
          surfaceContainerHighest: Color(0xFF111111),
        ),
        appBarTheme: base.appBarTheme.copyWith(backgroundColor: Colors.black, foregroundColor: Colors.white, centerTitle: false, elevation: 0),
        iconTheme: const IconThemeData(color: Colors.white),
        listTileTheme: base.listTileTheme.copyWith(dense: compact, visualDensity: VisualDensity.compact, iconColor: Colors.white),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.black,
          indicatorColor: Color(0xFF222222),
          iconTheme: WidgetStatePropertyAll(IconThemeData(color: Colors.white)),
          labelTextStyle: WidgetStatePropertyAll(TextStyle(color: Colors.white, fontSize: 12)),
        ),
        dividerColor: const Color(0xFF222222),
        sliderTheme: base.sliderTheme.copyWith(activeTrackColor: Colors.white, inactiveTrackColor: Color(0xFF444444), thumbColor: Colors.white),
        switchTheme: SwitchThemeData(
          thumbColor: const WidgetStatePropertyAll(Colors.white),
          trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF666666) : const Color(0xFF222222)),
        ),
        chipTheme: base.chipTheme.copyWith(backgroundColor: const Color(0xFF111111), labelStyle: const TextStyle(color: Colors.white)),
        dialogBackgroundColor: Colors.black,
        bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFF0A0A0A)),
      );
    } else {
      final base = ThemeData.light(useMaterial3: true);
      return base.copyWith(
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          secondary: Colors.black,
          surface: Colors.white,
          onSurface: Colors.black,
        ),
        appBarTheme: base.appBarTheme.copyWith(backgroundColor: Colors.white, foregroundColor: Colors.black, centerTitle: false, elevation: 1),
        iconTheme: const IconThemeData(color: Colors.black),
        listTileTheme: base.listTileTheme.copyWith(dense: compact, visualDensity: VisualDensity.compact, iconColor: Colors.black),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Color(0xFFE0E0E0),
          iconTheme: WidgetStatePropertyAll(IconThemeData(color: Colors.black)),
          labelTextStyle: WidgetStatePropertyAll(TextStyle(color: Colors.black, fontSize: 12)),
        ),
        sliderTheme: base.sliderTheme.copyWith(activeTrackColor: Colors.black, thumbColor: Colors.black),
      );
    }
  }
}

/// Presence dot — monochrome shades (online = solid, baaki grey steps, offline = faintest).
Color presenceColor(String status, {bool dark = true}) {
  switch (status) {
    case 'online':
      return dark ? Colors.white : Colors.black;
    case 'idle':
      return Colors.grey.shade500;
    case 'dnd':
      return Colors.grey.shade600;
    case 'streaming':
      return Colors.grey.shade400;
    default:
      return dark ? Colors.grey.shade800 : Colors.grey.shade300;
  }
}
