# Ripcord PC — Exact UI Map (binary + website se) aur hamare phone app ka Gap

Ripcord = Qt5 C++ desktop client (3-pane compact power-user UI, zero GPU, ~23MB RAM).
Neeche har screen ka inventory hai — `Ripcord.exe` strings + ripcord.rip/cancel.fm se nikala.

## A. Main window (exact Ripcord layout)
1. **Top menu bar**: File | View | Accounts | (Discord | Slack sub-menus) | Bookmarks | Help
2. **Left sidebar tree** (collapsible, bold = unread, badge = mention count):
   - Bookmarks section (top, user-pinned channels/DMs, folders, Collapse All)
   - Discord section per account: servers → categories → `#text` / `🔊voice` channels
   - Voice channel ke andar **connected users inline** (speaking = highlighted, muted/deaf icons, Priority Speaker)
   - Friends / Direct Messages section (open/close DMs, group DMs named by users, member counts)
   - Status bar bottom: account status (online/offline, per-account connect/disconnect), voice status
3. **Center = tabbed chat** (New Tab / Close Tab / Close Other Tabs, avoid redundant tabs, tabs for channels/DMs/Mentions/Friends/Accounts/Notifications/Event Log/Files/Pinned/Threads)
4. **Channel toolbar** (per tab): pins 📌, members 👥 toggle, notifications bell, emoji picker, file attach, Go-to/Quick-switcher
5. **Right panel (toggle)**: Channel Members grouped by role/presence (online green / offline grey), roles with colors, right-click user menu (DM, kick/ban/mute/deafen, copy tag, roles)
6. **Chat log**: author-grouped messages (avatar sized by font), timestamps, edited flag, deleted-messages view (mod), mentions highlighted, `#channel` + URL clickable, jumbo single-emoji, custom Discord emoji (cached in sqlite `.ripdb`), reactions row (toggle on click), attachments (image thumbnails, file titles, click-to-open), threads view, infinite scroll (fetch on scroll-up), typing indicator bar
7. **Input box**: auto-resize, `@user` + `:emoji:` tab-completion popup, Up-arrow quick-edit last message, right-click edit/delete/copy/copy-link, file drag-drop upload, send on Enter
8. **Quick switcher** (`Ctrl+K` "Go to..."): fuzzy find across all channels/DMs/users — Ripcord ki sabse loved feature
9. **Notifications view**: mentions list, dismiss/dismiss-all, follow-to-channel, OS popups + tray flash + sounds
10. **Accounts view (tab)**: multi-account (Discord+Slack), add (email/pass/token/browser-import), per-account connect/disconnect, encrypted token storage (`Saved account data is encrypted`)
11. **Voice UI**: join → call lane/window (`DisCallView`, `DisCallWindow`) with per-user rows (`DisVoiceLine`: avatar, name, volume, mute/deafen/server-mute, priority speaker), bottom voice bar, Push-to-Talk hotkey, gate threshold
12. **Preferences dialog** (exact pages — binary me mile):
    - General: auto-connect, check for updates, show Accounts tab on launch, avoid redundant tabs, minimize network usage
    - Style (`RipSettingsPage_Style`): dark/light theme, Chat Font + size, Code Font, sidebar font, avatars in chat on/off + size, chat emoji size, timestamps on/off, compact window borders
    - Notifications & Windowing: OS popups, sounds, tray icon, multi-window
    - Audio (`RipSettingsPage_Audio`): input/output `RipAudioDevicePicker`, **log-scale dB gain slider (`RipLogScaleDbSlider`, 0..+24dB)**, music-mode Opus checkbox, gate threshold, PTT + hotkey
    - Discord (`RipSettingsPage_Discord`): show own typing, read-state sync, moderator views
    - Slack / Proxy / Locale / Experimental pages
13. **Server admin views**: Roles, Members, Bans, Invites, Audit Log, Emoji, Channel perms/editor — (phone v1 me read-only ya skip)
14. **Event Log + Files views**: per-account debug/activity log, file shares list

## B. Hamare phone app me kya NAHI tha (gap — ab fix kiya)
| # | Ripcord feature | Hamare app me tha? | Ab |
|---|---|---|---|
| 1 | Server rail + categories + voice-users-inline wala channel tree | ❌ sirf flat drawer list | ✅ `ripcord_widgets.dart` ChannelTree |
| 2 | Tabs | ❌ | ✅ phone-adapted: bottom nav (Chats/Bookmarks/Mentions/Friends/Settings) + recent-stack |
| 3 | Quick switcher (Ctrl+K Go to) | ❌ | ✅ search dialog |
| 4 | Bookmarks | ❌ | ✅ local bookmarks tab + star toggle |
| 5 | Mentions view | ❌ | ✅ MESSAGE_CREATE me `@me` filter tab |
| 6 | Friends + DMs (open/close, add, accept/decline) | ❌ | ✅ Friends tab |
| 7 | Member list right drawer (role/presence grouped) | ❌ | ✅ endDrawer |
| 8 | Author-grouped messages, timestamps, reactions, attachments, jumbo emoji, edited flag | ❌ plain ListTile | ✅ MessageView |
| 9 | Typing indicator | ❌ | ✅ TYPING_START bar |
| 10 | Input with @/:emoji completion, send, edit/delete/copy | ❌ send hi nahi tha | ✅ chat_screen |
| 11 | Pins view, notification bell per channel | ❌ | ✅ toolbar + pins sheet |
| 12 | Preferences pages (Style/Notifications/Audio/Discord/Proxy/About) | ❌ sirf audio screen | ✅ settings_screen |
| 13 | Multi-account + encrypted token storage | ❌ single token | ✅ accounts (multi, secure storage) |
| 14 | Persistent voice bottom bar + per-user voice rows | ❌ alag screen only | ✅ VoiceBottomBar + voice users inline |
| 15 | Presence colors (online/offline), unread bold + mention badges | ❌ | ✅ |
| 16 | Light theme + font-size setting | ❌ dark fixed | ✅ Ripcord dark/light + sliders |
| 17 | Event Log / Audit / Roles / Bans admin | ❌ | ⏳ Phase-2 (desktop-admin, phone par low value) |
| 18 | Screen-share video | ❌ (Ripcord me bhi Partial ✗) | ⏳ skip — Ripcord me bhi nahi |

## C. Phone adaptation (exact copy nahi, exact feel)
Desktop 3-pane phone par fit nahi hota, isiliye Ripcord mapping:
- Menu bar → AppBar + overflow menu; Tabs → bottom nav + back-stack; Right members → endDrawer;
- Sidebar tree → server rail (64px) + channel drawer; Ctrl+K → 🔍 search button; Hover right-click → long-press menu.
- Baaki sab (grouping, badges, dB slider, prefs) 1:1 same logic.
