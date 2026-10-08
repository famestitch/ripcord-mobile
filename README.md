# Ripcord Mobile — phone Discord client (Flutter, Android+iOS)

Ripcord PC (Qt5, `Ripcord_Win_0.4.29`) ka phone port — **exact Ripcord UI feel**.
Deep analysis: `analysis/RIPCORD_AUDIO_ANALYSIS.md` (audio) + `analysis/RIPCORD_UI_MAP_AND_GAP.md` (UI map + gap list).

## Ripcord-exact UI (phone mapping)
| Ripcord PC | Phone app |
|---|---|
| Menu bar | AppBar + overflow menu |
| Sidebar tree (bookmarks → servers → categories → #text/🔊voice, voice users inline) | Server rail (64px) + channel drawer + body tree |
| Tabs | Bottom nav: Chats / Saved⭐ / Mentions@ / Friends / Settings |
| Ctrl+K "Go to…" quick switcher | 🔍 search button (channels + DMs) |
| Right member panel (role/presence) | Chat me endDrawer (👥 swipe) |
| Chat log (grouped, timestamps, reactions, attachments, jumbo emoji, custom emoji) | MessageView (same) |
| Typing bar, pins 📌, bell, @/:emoji: tab-completion, Up-edit, copy/edit/delete, attach | ChatScreen (same) |
| Call lane + voice bar (per-user rows, mute/deafen) | VoiceBottomBar (persistent) + VoiceScreen |
| Preferences (General/Style/Notifications/Audio/Discord/Proxy/About) | SettingsScreen (same pages) |
| Right-click menus | Long-press sheets |
| dB gain `RipLogScaleDbSlider` 0..+24dB | VoiceScreen slider (verified math) |

## Features abhi
- Login: **Token** (stable) + **Email+Pass** (reference — hCaptcha/MFA lag sakta hai), secure storage
- Servers rail, categories, voice-users-inline, unread/mention badges (custom, sab Flutter versions par)
- Send/edit/delete/copy-link messages, pins view, bookmarks, mentions feed, friends + open/close DMs
- **LOUDMIC voice TX (real)**: mic 48kHz mono RAW (echoCancel/noiseSuppress/autoGain
  sab OFF) + **real-time 0..+24dB gain slider** (Ripcord log-scale, click-free ramp,
  agle 20ms frame se live) + gate + Opus encode + sodium encrypt + UDP,
  region-bypass transport ke upar. VoiceScreen me LIVE mic meter hai. (RX decode
  ready hai, speaker playback wiring baaki.)
- Pure black & white theme, chat/sidebar font sliders, avatars/timestamps/compact toggles

## ⚠️ Pehle padho
3rd-party user-client **Discord ToS ke against** hai — **pehle ALT/test account** se try karo,
main account se nahi. Email+pass par hCaptcha aayega to browser me login karke token use karo.

## APK kaise banaye (2 raste)
**Rasta A — GitHub Actions (PC ki zarurat nahi, phone se bhi hoga):**
1. Is folder ko GitHub repo me push karo.
2. Repo me Actions tab → "Build APK" → Run workflow (push par auto bhi chalta hai).
3. Artifacts se `ripcord-mobile-apk` download karke install karo. Workflow file:
   `.github/workflows/build-apk.yml` (pehle se likhi hai).

**Rasta B — apne PC par (Android SDK + NDK chahiye — sodium build hooks NDK se compile hota hai):**
```bash
flutter pub get
flutter analyze        # static check
flutter run            # USB phone / emulator
flutter build apk      # Android APK (release; debug ke liye --debug lagao)
```
`android/` scaffold repo me hai (minSdk 23, mic permissions, black launch theme).
Pehli install par mic permission allow karna + ALT account token se login.

## Abhi kya NAHI hai (Phase-2)
1. Speaker playback (RX decrypt+decode ready hai, AudioTrack/player wiring baaki)
2. RNNoise extra (OS-level noiseSuppress pehle se ON hai) / message search
3. Server-admin views (Roles/Bans/Invites/Audit) — desktop-admin, phone par low value
4. File upload (`/attachments` TODO)

## Files
- `lib/session.dart` — shared state (gateway events → UI: messages/typing/mentions/voice-states)
- `lib/audio/gain.dart`, `lib/audio/voice_engine.dart` — dB math + gain/gate/Opus params
- `lib/discord/rest.dart|gateway.dart` — REST + Gateway/Voice signalling
- `lib/discord/voice_connection.dart` — region-bypass transport (WS+UDP+RTP clock)
- `lib/discord/loudmic_backend.dart` — REAL mic→gain→Opus→sodium backend (record/opus_dart/opus_flutter/sodium pkgs)
- `lib/discord/voice_audio_backend.dart` — backend interface + settings fields
- `lib/ui/ripcord_theme.dart` — Style page prefs (dark/light, fonts, density)
- `lib/ui/ripcord_widgets.dart` — rail, tree, messages, members, quick-switcher, voice bar
- `lib/ui/chat_screen.dart`, `tabs_screens.dart`, `settings_screen.dart`, `voice_screen.dart`, `home_screen.dart`
