# Ripcord PC (Ripcord_Win_0.4.29) — Audio Processing Deep Analysis
# Source: https://github.com/famestitch/ripcord-by-raze-source
# Date: 2026-10-08 — reverse-engineered from binaries (repo me SOURCE CODE NAHI HAI)

## 1. Pehle sach: ye repo "source" nahi hai
Repo me sirf ye hai, koi `.cpp/.h` nahi:
- `Qt5*.dll` (Core, Gui, Widgets, Network, WebSockets, Multimedia)
- `opus.dll` (libopus codec), `libsodium.dll` (encryption)
- `qtaudio_wasapi.dll` + `qtaudio_windows.dll` (Qt audio backend plugins)
- `Ripcord_Win_0.4.29.zip` ke andar asli `Ripcord.exe` (~5.5MB, Qt 5.9.7, MSVC2017 64-bit, path: `C:\Users\cancel\ripcord\build-...-Release\Ripcord.pdb`)

Matlab audio logic humne `strings Ripcord.exe` se nikala hai. 100% line-by-line source nahi mil sakta, lekin pipeline poori tarah clear hai.

## 2. Audio pipeline (PC)
```
[Mic] -> QAudioInput (WASAPI) -> QIODevice buffer
  -> Float32 @ 48kHz mono (opus_encode_float)
  -> Opus encode (opus_encoder_create/ctl, bitrate set, voice-vs-music mode)
  -> XSalsa20-Poly1305 encrypt (libsodium: legacy + suffix modes)
  -> QUdpSocket UDP send + Voice WebSocket heartbeat (VOICE_STATE_UPDATE / VOICE_SERVER_UPDATE)

[UDP recv] -> libsodium decrypt -> opus_decode_float -> per-user mixer
  (DisCallViewInputWorker / DisCallViewOutputWorker / DisVoiceLine / DisVoiceLineSink / VoiceSink)
  -> QAudioOutput (WASAPI) -> [Speaker]
```

Proof strings:
- `opus_encode_float / opus_decode_float / opus_encoder_create / opus_encoder_ctl / Opus bitrate set error / Opus encoding creation error`
- `QAudioInput / QAudioOutput / QAudioDeviceInfo / qtaudio_wasapi.dll / qtaudio_windows.dll`
- `QUdpSocket / readDatagram / writeDatagram / Opening Voice WebSocket connection / Starting voice socket thread heartbeat`
- `Libsodium failed to decrypt voice data (legacy mode) / (suffix mode) / Unresolvable voice encryption mode`
- `DisCallViewInputWorker / DisCallViewOutputWorker / DisCallViewInputIODevice / DisCallViewOutputIODevice / DisVoiceLineSink`
- `RipAudioDevicePicker / RipSettingsPage_Audio / defaultInputDevice / defaultOutputDevice / isFormatSupported`

## 3. "24 dB" wala option kya hai?
- Custom widget: `RipLogScaleDbSlider` (log-scale dB slider — linear nahi, kaan ke hisaab se)
- Label string: `Gain`
- Voice Activity gate: `gateThresholdChangedByGui`
- Settings strings: `Microphone Mode / Output Device / Voice Output / Push to Talk / Push to Talk Hotkey / Priority Speaker`
- Opus mode strings: `Force Opus codec to encode in music mode / Do not enable this unless you are broadcasting music. / Enabling this will decrease voice quality.`

Matlab:
- Mic input gain = linear multiplier `g = 10^(dB/20)`. +24 dB ≈ 15.85x amplitude.
- Ripcord me slider log-scale hai taaki 0..6dB me fine control, 18..24dB me tez badhe.
- Uske saath Voice Activity gate threshold + PTT hai. Gain badhane par gate threshold bhi upar karna padta hai warna noise trigger hoga.
- Koi RNNoise / WebRTC AEC / AGC / NS **nahi mila** binary me. Isiliye "isse better" banana aasaan hai — hum phone me noise-suppression + echo-cancel add karenge.

## 4. Phone (Android/iOS) me iska equivalent
| PC (Ripcord/Qt) | Phone native |
|---|---|
| QAudioInput/QAudioOutput + WASAPI | Android: Oboe/AAudio `AudioRecord` (VOICE_COMMUNICATION) + `AudioTrack`; iOS: AVAudioSession + AudioUnit/VoiceProcessingIO |
| opus.dll encode_float/decode_float 48kHz mono | Mobile: libopus (JNI / C interop), 48kHz mono, 20ms frame (960 samples), bitrate 32-64kbps voice, FEC + DTX on |
| libsodium XSalsa20-Poly1305 | libsodium (JNI / swift-sodium), modes: `xsalsa20_poly1305`, `xsalsa20_poly1305_suffix`, `aead_aes256_gcm` (Discord voice gateway v8) |
| QUdpSocket + Voice WS heartbeat | UDP socket (Kotlin/Swift) + Gateway v6 + Voice Gateway v8 (`VOICE_STATE_UPDATE`, `VOICE_SERVER_UPDATE`, IP discovery, SRTP-like header) |
| RipLogScaleDbSlider 0..+24dB | Wahi formula phone me (neeche `lib/audio/gain.dart` me port kiya hai) |
| Qt Widgets UI (~50MB RAM) | Flutter native UI (~same lightweight, Ripcord jaisa 3-pane: servers | channels | chat + bottom voice bar) |

## 5. Discord voice protocol (phone client ko ye karna padega)
1. REST login -> Gateway (wss://gateway.discord.gg) IDENTIFY -> GUILDs + channels list
2. Voice join: `VOICE_STATE_UPDATE {guild_id, channel_id}` -> server replies `VOICE_SERVER_UPDATE {token, endpoint}` + `VOICE_STATE_UPDATE {session_id}`
3. Voice WS (wss://endpoint): HELLO -> IDENTIFY {server_id, user_id, session_id, token} -> READY {ssrc, ip, port, modes, secret_key}
4. UDP IP discovery -> SELECT_PROTOCOL {protocol: udp, data: {address, port, mode}} -> SESSION_DESCRIPTION {secret_key, mode}
5. RTP header (12 byte) + Opus frame + nonce encrypt karke UDP send; recv karke decrypt+decode+mix.
6. Heartbeat har interval par, sequence/timestamp 48kHz clock se badhao.

## 6. Login warning (zaruri)
- Email+password login official API par hCaptcha + MFA + rate-limit lagta hai, aur **3rd-party client Discord ToS ke against hai — account ban ho sakta hai.**
- Is scaffold me 3 login rakhe hain: token (dev/test ke liye sabse stable), email+pass (sirf reference, captcha handle karna padega), QR (phone-as-secondary). Pehle apne alt/test account se try karo.
