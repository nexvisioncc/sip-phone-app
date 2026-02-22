# SIP Phone App - Project Overview

## Goal
Build a native Android SIP phone app using Flutter that receives incoming calls from Twilio SIP trunk.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Mobile App | Flutter (Android) |
| SIP/VoIP | `flutter_sip` or `flutter_webrtc` + custom SIP |
| Signaling | WebSocket server (Node.js/Go) |
| Push Notifications | Firebase Cloud Messaging (FCM) |
| Backend API | REST API on k8s |
| SIP Trunk | Twilio Elastic SIP Trunking |
| Media Relay | coturn (STUN/TURN) on k8s |

## Key Flutter Packages

```yaml
dependencies:
  flutter_sip: ^latest          # SIP signaling
  flutter_webrtc: ^latest       # WebRTC for media
  firebase_messaging: ^latest   # Push notifications
  flutter_callkit_incoming: ^latest  # Native call UI
  permission_handler: ^latest   # Microphone permissions
  shared_preferences: ^latest   # Local settings storage
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Android Phone                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Flutter SIP Phone App                  │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │   │
│  │  │  Call UI    │  │  Contacts   │  │  Settings   │ │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘ │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │   │
│  │  │ flutter_sip │  │flutter_webrtc│  │firebase_messaging│ │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────┘
                           │ WebSocket (SIP signaling)
                           │ WebRTC (media)
                           │ HTTPS (API)
┌──────────────────────────▼──────────────────────────────────┐
│                     Kubernetes Cluster                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │  SIP Proxy  │  │  Signaling  │  │   REST API Server   │ │
│  │  (Kamailio) │  │  WebSocket  │  │   (Node.js/Go)      │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │  coturn     │  │   Redis     │  │   PostgreSQL        │ │
│  │ (STUN/TURN) │  │  (sessions) │  │   (persist data)    │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└──────────────────────────┬──────────────────────────────────┘
                           │ SIP Trunk
┌──────────────────────────▼──────────────────────────────────┐
│                     Twilio                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Elastic SIP Trunking                        │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │   │
│  │  │ Phone Number│  │  SIP URI    │  │  Voice API  │ │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Call Flow - Incoming Call

```
1. External caller dials Twilio number
         │
         ▼
2. Twilio SIP trunk forwards to your k8s SIP proxy
         │
         ▼
3. Kamailio receives INVITE, looks up registered device
         │
         ▼
4. Device offline? → Send push via FCM
         │
         ▼
5. App wakes, registers SIP, receives INVITE
         │
         ▼
6. flutter_callkit_incoming shows native call UI
         │
         ▼
7. User answers → WebRTC media flow via coturn
```

## Infrastructure Components Needed

| Component | Purpose | Deploy To |
|-----------|---------|-----------|
| Kamailio | SIP proxy/registrar | k8s (StatefulSet) |
| Signaling WS | WebSocket for mobile SIP | k8s (Deployment) |
| coturn | STUN/TURN for NAT traversal | k8s (DaemonSet or VPS) |
| API Server | User auth, device registration | k8s (Deployment) |
| Redis | Session store, presence | k8s (StatefulSet) |
| PostgreSQL | User data, call logs | k8s (StatefulSet) |

## Next Steps

1. [ ] Set up Flutter project structure
2. [ ] Deploy Kamailio + coturn to k8s
3. [ ] Configure Twilio SIP trunk
4. [ ] Build basic SIP registration
5. [ ] Implement incoming call with push
6. [ ] Add call UI and controls
