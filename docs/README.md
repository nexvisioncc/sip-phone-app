# Nexvision SIP Phone App — Architecture & Operations Guide

## Overview

A production-grade mobile VoIP app that lets a Flutter Android app make and receive PSTN calls
via Twilio, bridged through Asterisk B2BUA and a Node.js signaling backend on Kubernetes.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          PSTN / CALLER                              │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ (dials Twilio number)
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            TWILIO                                   │
│  Programmable Voice (Incoming)         Elastic SIP Trunk (Outgoing) │
│  Webhook: https://voice.nexvision.cc   Termination: *.pstn.twilio.com│
│  /twilio/incoming                      IP ACL: 172.93.53.224        │
└───────────────┬──────────────────────────────────┬──────────────────┘
                │ HTTP webhook (incoming)           │ SIP/TCP (outgoing)
                ▼                                  │
┌───────────────────────────┐                      │
│   ai-voice-receptionist   │                      │
│   (namespace: openclaw)   │                      │
│   voice.nexvision.cc      │                      │
│   Responds with TwiML:    │                      │
│   <Dial><Sip> to Asterisk │                      │
└───────────────┬───────────┘                      │
                │ SIP INVITE (TCP port 5060)        │
                ▼                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│             ASTERISK B2BUA  (namespace: sip-phone)                  │
│             hostNetwork:true  — 172.93.53.224                       │
│                                                                     │
│  pjsip.conf endpoints:                                              │
│  ┌──────────────────┐  ┌───────────────────┐  ┌─────────────────┐  │
│  │ [herberttung]    │  │ [twilio]          │  │ [twilio-out]    │  │
│  │ transport=ws     │  │ context=from-twilio│  │ context=any     │  │
│  │ webrtc=yes       │  │ ip-match          │  │ aor=trunk host  │  │
│  │ context=from-    │  │ (Twilio IP ranges │  │ (outbound PSTN) │  │
│  │   internal       │  │ + 10.42.0.0/16)   │  │                 │  │
│  └───────┬──────────┘  └────────┬──────────┘  └────────┬────────┘  │
│          │                      │                       │           │
│  extensions.conf:               │                       │           │
│  [from-internal]                │ [from-twilio]         │           │
│  Dial(PJSIP/${EXTEN}            │ Dial(PJSIP/herberttung│           │
│       @twilio-out)              │ ,30)                  │           │
│                                 │                       │           │
│  RTP media: UDP 10000-10099 ────┼───────────────────────┘           │
└───────────────┬─────────────────┴───────────────────────────────────┘
                │ SIP-over-WebSocket  ws://asterisk:8080/ws
                ▼
┌─────────────────────────────────────────────────────────────────────┐
│            sip-api  Node.js Backend  (namespace: sip-phone)         │
│            Ingress: wss://sip-api.nexvision.cc/ws                   │
│                                                                     │
│  Maintains ONE persistent SIP WS connection to Asterisk.            │
│  Registered as: herberttung@sip.nexvision.cc                        │
│                                                                     │
│  Incoming call flow:                                                │
│    Asterisk INVITE → parse SDP offer → forward to Flutter WS        │
│    Flutter answer SDP → send 200 OK to Asterisk                     │
│                                                                     │
│  Outgoing call flow:                                                │
│    Flutter {call, number, sdp_offer} → send INVITE to Asterisk      │
│    Asterisk 180/200 + SDP answer → forward to Flutter               │
│    Flutter sets remote desc → ICE connects → audio                  │
│                                                                     │
│  FCM push: on INVITE → sendFcmPush() → wakes locked phone           │
│  REST: POST /devices (FCM token), GET /health, POST /test-call      │
└───────────────┬─────────────────────────────────────────────────────┘
                │ wss://sip-api.nexvision.cc/ws  (WebSocket JSON)
                ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Flutter Android App  (cc.nexvision.sip_phone_app)      │
│                                                                     │
│  CallService (singleton)                                            │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ WS connection → backend  (auto-reconnect, 25s ping)          │   │
│  │ answer(sdpOffer) → WebRTC peer connection (ICE/DTLS/SRTP)    │   │
│  │ call(number)    → WebRTC offer → backend → Asterisk → PSTN   │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  flutter_webrtc: ICE/DTLS/SRTP media directly to Asterisk          │
│  RTP path: Phone ←→ (SRTP) ←→ Asterisk ←→ (RTP) ←→ Twilio/PSTN   │
│                                                                     │
│  flutter_callkit_incoming: native call UI (full-screen on lock)     │
│  firebase_messaging: FCM data push → wakes backgrounded app        │
│  flutter_background_service: keeps WS alive when backgrounded      │
│  flutter_sound: call recording → Documents/recordings/*.aac        │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Incoming Call Flow (PSTN → Flutter)

```
1. PSTN caller dials Twilio number
2. Twilio fires HTTP POST to https://voice.nexvision.cc/twilio/incoming
3. ai-voice-receptionist responds with TwiML:
     <Response><Dial><Sip>sip:herberttung@172.93.53.224:5060;transport=tcp</Sip></Dial></Response>
4. Twilio sends SIP INVITE to Asterisk (TCP port 5060)
5. Asterisk matches [twilio-identify] → context from-twilio
     Dial(PJSIP/herberttung, 30)
6. Asterisk sends SIP INVITE to sip-api backend (via WebSocket)
7. sip-api:
   a. Sends 100 Trying + 180 Ringing to Asterisk
   b. Extracts SDP offer from INVITE body
   c. Forwards {type:incoming_call, call_id, from, sdp_offer} to Flutter WS
   d. Sends FCM push if Flutter WS is not connected (phone locked/backgrounded)
8. Flutter receives incoming_call or FCM push:
   a. FlutterCallkitIncoming shows native call UI
   b. User taps Accept → CallService.answer()
   c. Creates WebRTC peer connection (ICE/DTLS/SRTP)
   d. Gathers ICE candidates (STUN: stun.l.google.com:19302)
   e. Sends {type:answer, call_id, sdp_answer} to backend
9. sip-api sends 200 OK with SDP answer to Asterisk
10. Asterisk sends ACK → sip-api sends {type:call_state, state:active}
11. ICE connects → DTLS handshake → SRTP audio flows:
       Phone ←(SRTP/ICE)→ Asterisk ←(RTP)→ Twilio ←(PSTN)→ Caller
```

---

## Outgoing Call Flow (Flutter → PSTN)

```
1. User dials number in Flutter app → taps Call
2. Flutter CallService.call(number):
   a. Requests mic permission
   b. Creates WebRTC peer connection
   c. Captures mic (getUserMedia, all processing disabled)
   d. Adds audio track, creates SDP offer
   e. Gathers ICE candidates
   f. Sends {type:call, number, sdp_offer, call_id} to backend
3. sip-api sends SIP INVITE to Asterisk with Flutter's SDP offer
     INVITE sip:+16477068280@sip.nexvision.cc SIP/2.0
     (body: Flutter's WebRTC SDP offer)
4. Asterisk context from-internal:
     Set(CALLERID(num)=+1XXXXXXXXXX)   ; Twilio number
     Dial(PJSIP/+16477068280@twilio-out, 60)
5. Asterisk sends INVITE to Twilio SIP Trunk (TCP)
     INVITE sip:+16477068280@{trunk}.pstn.twilio.com
6. Twilio dials PSTN, returns 180 Ringing → Asterisk → sip-api
7. sip-api forwards {type:call_state, state:ringing} → Flutter shows "Ringing..."
8. PSTN answers → Asterisk sends 200 OK with SDP answer to sip-api
9. sip-api:
   a. Sends ACK to Asterisk
   b. Sends {type:call_state, state:active, sdp_answer} to Flutter
10. Flutter sets remote description (Asterisk's SDP answer)
11. ICE connects → DTLS → SRTP audio:
       Phone ←(SRTP/ICE)→ Asterisk ←(RTP)→ Twilio ←(PSTN)→ Called party
```

---

## Backend WebSocket Protocol

### Flutter → Backend

| Message | Fields | Description |
|---------|--------|-------------|
| `call` | `number`, `sdp_offer`, `call_id` | Initiate outgoing PSTN call |
| `answer` | `call_id`, `sdp_answer` | Accept incoming call |
| `reject` | `call_id` | Decline incoming call |
| `hangup` | `call_id` | End active call |
| `dtmf` | `call_id`, `tone` | Send DTMF digit |

### Backend → Flutter

| Message | Fields | Description |
|---------|--------|-------------|
| `registered` | — | SIP registration confirmed |
| `incoming_call` | `call_id`, `from`, `sdp_offer` | Incoming call with SDP |
| `call_state` | `call_id`, `state`, `sdp_answer?` | Call progress |
| `error` | `message` | Server error |

**`call_state` values:** `dialing`, `ringing`, `active`, `ended`, `failed`
- Outgoing only: `active` includes `sdp_answer` (WebRTC answer from Asterisk)

---

## Kubernetes Components

| Resource | Namespace | Purpose |
|----------|-----------|---------|
| `deploy/asterisk` | sip-phone | Asterisk B2BUA (hostNetwork, RTP 10000-10099) |
| `deploy/sip-api` | sip-phone | Node.js WS bridge + REST API |
| `ingress/sip-api` | sip-phone | `wss://sip-api.nexvision.cc/ws` (timeout 3600s) |
| `deploy/ai-voice-receptionist` | openclaw | Twilio webhook handler |
| `ingress/voice` | openclaw | `https://voice.nexvision.cc/twilio/incoming` |

### Key Environment Variables (sip-api)

| Variable | Value | Description |
|----------|-------|-------------|
| `GOOGLE_APPLICATION_CREDENTIALS` | `/secrets/firebase-service-account.json` | FCM credentials |
| `PORT` | `3000` | HTTP port |

SIP credentials are hardcoded in server.js: `SIP_USER=herberttung`, `SIP_DOMAIN=sip.nexvision.cc`.

---

## Twilio Setup

### Incoming Calls (already working)

1. Twilio Console → Phone Numbers → your number → Voice → Webhook
2. Set to: `https://voice.nexvision.cc/twilio/incoming` (HTTP POST)
3. `ai-voice-receptionist` responds with TwiML forwarding to Asterisk

### Outgoing Calls (Twilio Elastic SIP Trunking — one-time setup)

1. **Create an Elastic SIP Trunk**
   - Twilio Console → Elastic SIP Trunks → Create Trunk
   - Give it a name (e.g. "Nexvision Outbound")

2. **Configure Termination (outbound from Asterisk → Twilio)**
   - Open the trunk → Termination tab
   - Note the **Termination SIP URI** (e.g. `sk-XXXXXXXX.pstn.twilio.com`)
   - Under "IP Access Control Lists", add `172.93.53.224` (server public IP)
     - This allows Asterisk to dial out without a username/password

3. **Update Asterisk config** (`k8s/02-asterisk.yaml`):
   ```yaml
   # In pjsip.conf, find [twilio-out] aor section:
   contact=sip:sk-XXXXXXXX.pstn.twilio.com   # ← paste your trunk hostname

   # In extensions.conf [from-internal]:
   Set(CALLERID(num)=+14165551234)            # ← your Twilio phone number
   ```

4. **Apply and restart**:
   ```bash
   export KUBECONFIG=C:/Users/herbe/.gemini/antigravity/skills/k3s-config.yaml
   kubectl apply -f k8s/02-asterisk.yaml -n sip-phone
   kubectl rollout restart deploy/asterisk -n sip-phone
   ```

5. **Verify**: Tail Asterisk logs and place a test outgoing call from the app
   ```bash
   kubectl logs -f deploy/asterisk -n sip-phone
   ```

---

## Flutter App Structure

```
flutter_app/lib/
├── main.dart                     # App entry, FCM/background setup
├── config/constants.dart         # SharedPreferences keys, defaults
├── models/recording.dart         # Recording data model
├── screens/
│   ├── main_screen.dart          # Bottom nav shell (IndexedStack)
│   ├── dialer_screen.dart        # Numpad + outgoing call button
│   ├── call_screen.dart          # Active call UI (in/out), DTMF, record
│   ├── recents_screen.dart       # Call history + recording playback
│   ├── contacts_screen.dart      # Contact list
│   └── settings_screen.dart     # SIP settings, WS status, toggles
└── services/
    ├── sip_service.dart          # CallService: WS bridge, WebRTC, call()
    ├── api_service.dart          # REST: FCM token registration
    ├── push_service.dart         # FCM + CallKit integration
    ├── recording_service.dart    # flutter_sound recording/playback
    └── background_service.dart   # flutter_background_service foreground
```

### Key Services

**CallService** (`sip_service.dart`) — singleton, manages everything:
- `connect(wsUrl)` — opens WS to backend, auto-reconnects every 5s
- `answer()` — accepts incoming call: audio session → prime pipeline → PC → getUserMedia → SDP answer → ICE → send to backend
- `call(number)` — places outgoing call: audio session → prime pipeline → PC → getUserMedia → SDP offer → ICE → send to backend
- `hangup()` / `reject()` — send hangup/reject to backend
- `toggleMute()` — enables/disables local audio track
- `sendDTMF(tone)` — sends SIP INFO DTMF via backend

**Audio pipeline priming** (`_primeAudioPipeline`):
- Creates a throwaway loopback (PC1 ↔ PC2) to warm up Android's AudioRecord
- Required on Samsung Galaxy devices: without it, the mic is silent for the first ~2s
- All SW audio processing disabled (`echoCancellation:false` etc.) to avoid conflicts with Samsung HW AEC

---

## Settings & SharedPreferences Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `sip_username` | String | `herberttung` | SIP username |
| `sip_password` | String | `87828Idiot` | SIP password |
| `sip_domain` | String | `sip.nexvision.cc` | SIP domain |
| `display_name` | String | `Nexvision` | Caller display name |
| `api_url` | String | `https://sip-api.nexvision.cc` | Backend REST URL |
| `ws_url` | String | `wss://sip-api.nexvision.cc/ws` | Backend WS URL |
| `auto_record` | bool | false | Auto-start recording on call connect |
| `run_in_background` | bool | false | Enable foreground service |
| `show_incoming_notification` | bool | true | Show CallKit/incoming UI |

---

## Deployment

### Apply all configs

```bash
export KUBECONFIG=C:/Users/herbe/.gemini/antigravity/skills/k3s-config.yaml

kubectl apply -f k8s/02-asterisk.yaml -n sip-phone
kubectl apply -f k8s/03-api-server.yaml -n sip-phone
kubectl apply -f k8s/05-ingress.yaml -n sip-phone
```

### Build & run Flutter app

```bash
# Debug run on emulator
/c/Users/herbe/flutter/bin/flutter run --debug -d emulator-5554

# Build debug APK + install on Samsung
/c/Users/herbe/flutter/bin/flutter build apk --debug
adb -s <device> install -r build/app/outputs/flutter-apk/app-debug.apk

# Test incoming call via FCM (no real SIP needed)
curl -X POST https://sip-api.nexvision.cc/test-call \
  -H 'Content-Type: application/json' \
  -d '{"caller":"Test User"}'
```

### Health check

```bash
curl https://sip-api.nexvision.cc/health
# Returns: {"status":"ok","sip_connected":true,"sip_registered":true,"flutter_connected":true}
```

---

## Known Issues & Notes

- **Outgoing calls**: Require Twilio Elastic SIP Trunk setup (see above). Until configured, calls will fail with SIP 21 (User unavailable).
- **Samsung mic silence**: Solved with `_primeAudioPipeline()` + all SW audio processing disabled.
- **Doze mode (Android 15)**: Add app to doze whitelist: `adb shell dumpsys deviceidle whitelist +cc.nexvision.sip_phone_app`
- **Full-screen intent (Android 14+)**: `adb shell appops set cc.nexvision.sip_phone_app USE_FULL_SCREEN_INTENT allow`
- **Background process crash (Android 16)**: Fixed via custom `Application.kt` that registers notification channels in `onCreate()` for all processes.
- **Incoming call answer race**: Fixed — do NOT call `FlutterCallkitIncoming.endCall()` before/during `answer()`.
- **WS keepalive**: Backend pings Asterisk every 20s, pings Flutter clients every 25s.
- **ICE**: Uses `stun.l.google.com:19302`. No TURN server needed (Asterisk is on public IP 172.93.53.224).
