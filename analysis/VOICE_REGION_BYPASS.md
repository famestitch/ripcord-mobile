# Voice Region-Change Bypass — design note

## Problem
Discord kabhi bhi voice server badal deta hai (guild region change, failover,
migration). Tab gateway se naya `VOICE_SERVER_UPDATE {token, endpoint}` aata hai.
Naive client (purana Ripcord-flow jaisa: teardown + full rejoin) me:
- mic capture ruk jata hai, Opus encoder reset, RTP seq/timestamp zero,
- dobara handshake me rejoin/ack bhool → **client hamesha ke liye chup**.

## Bypass (lib/discord/voice_connection.dart)
- **Mic pipeline + encoder + RTP clock (seq/ts/ssrc) kabhi reset nahi hote.**
  Region change par sirf WS+UDP+key ka re-handshake hota hai (`_migrate()`).
- Migration ke dauran bane Opus frames queue (25 frames ~0.5s), ready hote hi flush.
- Pehle **RESUME (op7)** try, 4s timeout par fresh **IDENTIFY** — automatic.
- WS drop par auto-reconnect (resume-first). `endpoint==null` par state hold + rejoin retry.
- Kick/disconnect (4014 jaisa: `VOICE_STATE_UPDATE` me `channel_id==null`) par
  gateway se khud **op4 rejoin** (`onNeedRejoin` → Session) — user ko kuch nahi karna.
- Encryption modes priority: `aead_aes256_gcm_rtpsize` > `aead_xchacha20_poly1305_rtpsize` >
  `xsalsa20_poly1305_suffix` > `xsalsa20_poly1305` (Ripcord sirf suffix/legacy karta tha).
- Backend missing ho to status `audio-backend-missing` me 5s retry — native wiring
  judte hi media live, rejoin ki zarurat nahi.

## Event flow (Session)
- `VOICE_SERVER_UPDATE` → `voiceConn.updateServer(token, endpoint)`
  (same endpoint+token = no-op; different = seamless migrate).
- own `VOICE_STATE_UPDATE` → `voiceConn.updateSession(session_id)`;
  `channel_id==null` → `voiceConn.kicked()` (auto-rejoin).
- UI status: idle | joining | connecting | migrating | connected |
  reconnecting | waiting-for-server | audio-backend-missing
  (VoiceBottomBar + VoiceScreen me grey text me dikhta hai).

## Physical limit (honest)
Network gap ke beech ke packets physically nahi ja sakte — lekin client kabhi
mute/stuck nahi hota: clock continuous rehta hai, queue flush hota hai, aur
transmit resume automatic hai. Wahi "chahe jo bhi ho bandh nahi" ka matlab hai.

## Abhi baaki (media backend)
`voice_audio_backend.dart` me interface ready hai; default `StubVoiceAudioBackend`
saaf error deta hai. Phase-2: libopus FFI (encode/decode 48k mono 20ms) +
libsodium FFI (nonce rules file me documented) + Android AudioRecord / iOS
VoiceProcessingIO capture. Transport logic `PassthroughTestBackend` se bina
native ke test ho sakta hai (local loopback only — Discord par kabhi na bhejo).
