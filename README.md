# SIP Phone App Architecture

This repository contains the infrastructure, backend, and frontend code for the SIP Phone application. It bridges the Twilio PSTN network with a custom Flutter WebRTC mobile client, and integrates with the Retel AI voice receptionist.

## Architecture Overview

The system consists of three main segments:
1. **Twilio** (PSTN gateway and SIP Trunking)
2. **Kubernetes Gateway & Backend** (Asterisk, Node.js SIP API)
3. **Flutter Mobile App** (WebRTC SIP client)

### Incoming Call Flow (Twilio → User/AI)

```mermaid
sequenceDiagram
    participant PSTN as PSTN Caller
    participant Twilio as Twilio
    participant OpenClaw as Retel AI (openclaw)
    participant Asterisk as K8s Asterisk
    participant API as K8s SIP API
    participant FCM as Firebase (FCM)
    participant App as Flutter App

    PSTN->>Twilio: Incoming Call
    Twilio->>Twilio: Webhook Routing (by Number)
    
    alt Route to Retel AI
        Twilio->>OpenClaw: Forward to AI Receptionist
        OpenClaw->>Asterisk: Transfer/Bridge to user (if requested)
    else Route to Phone App directly
        Twilio->>Asterisk: SIP INVITE (port 5060)
    end
    
    Asterisk->>API: SIP INVITE (WebSocket)
    API->>FCM: Push Notification (Wake up device)
    FCM->>App: FCM Payload
    App->>API: Connect WebSocket
    API->>App: Forward SIP INVITE / Ringing
    App->>API: Answer (SDP Offer/Answer)
    API->>Asterisk: SIP 200 OK (SDP)
    Asterisk->>Twilio: SIP 200 OK
    App<-->Asterisk: WebRTC Media (RTP/ICE/DTLS)
    Asterisk<-->Twilio: Plain RTP Media
```

1. A call arrives at **Twilio**. Based on the phone number's webhook configuration, Twilio routes it appropriately.
2. The call can go to **Retel AI (ai-voice-receptionist)** in the K3s `openclaw` namespace, or directly to the **Asterisk B2BUA**.
3. **Asterisk** handles the incoming SIP INVITE. It is configured to bridge plain RTP from Twilio to WebRTC for the Flutter app.
4. Asterisk passes the signaling via WebSocket to the **SIP API server (Node.js)**.
5. The **SIP API** acts as a signaling proxy. It sends a push notification via **Firebase Cloud Messaging (FCM)** to wake up the Flutter app.
6. The **Flutter App** receives the push, connects to the SIP API via WebSocket, and answers the call.
7. **Asterisk** proxies the RTP media directly to/from the Flutter app using WebRTC standards (ICE, DTLS-SRTP), transcoding or bridging to Twilio's plain RTP.

### Outgoing Call Flow (App → PSTN)

```mermaid
sequenceDiagram
    participant App as Flutter App
    participant API as K8s SIP API (Node.js)
    participant Asterisk as K8s Asterisk
    participant Twilio as Twilio SIP Trunking
    participant PSTN as PSTN

    App->>API: App places call (WebSocket, SDP Offer)
    API->>Asterisk: SIP INVITE (WebSocket)
    Asterisk->>Twilio: SIP INVITE (TCP/UDP)
    Twilio->>PSTN: Route call via SIP Trunk
    PSTN-->>Twilio: Ringing / Answer
    Twilio-->>Asterisk: 200 OK
    Asterisk-->>API: 200 OK (SDP Answer)
    API-->>App: Call Active (SDP Answer)
    App<-->Asterisk: WebRTC Media (RTP/ICE/DTLS)
    Asterisk<-->Twilio: Plain RTP Media
```

1. The **Flutter App** initiates a call by creating a WebRTC peer connection and sending an SDP offer to the **SIP API** via WebSocket.
2. The **SIP API** translates this into a SIP INVITE and sends it to **Asterisk**.
3. **Asterisk** matches the outgoing context and forwards the call to the **Twilio SIP Trunk** (`nexvision.pstn.twilio.com`).
4. **Twilio** routes the call to the PSTN.
5. Once answered, media flows securely via WebRTC between the Flutter App and Asterisk, and via plain RTP between Asterisk and Twilio.

## Key Components

### 1. K8s Asterisk Gateway (`k8s/02-asterisk.yaml`)
Replaces traditional OpenSIPS. Configured as a Back-to-Back User Agent (B2BUA).
- **Network**: Uses `hostNetwork: true` to expose RTP ports (10000-10099) directly to the public internet for WebRTC ICE negotiation.
- **Signaling**: Accepts TCP/UDP 5060 from Twilio and provides a WebSocket listener on 8080 for the SIP API.
- **Transcoding**: Bridges between Twilio's standard SIP/RTP and the Flutter App's WebRTC (DTLS-SRTP).

### 2. K8s SIP API (`k8s/03-api-server.yaml` & `backend/`)
A structured Node.js express application deployed in Kubernetes.
- Acts as a middleman between the Flutter App and Asterisk, avoiding direct mobile-to-Asterisk connectivity issues.
- Authenticates SIP endpoints via digest proxying.
- **Firebase integration**: Holds the `firebase-service-account` to send reliable push notifications to the mobile app when incoming calls arrive, ensuring the app wakes up even when backgrounded or killed.

### 3. Flutter Phone App (`flutter_app/`)
A custom SIP/WebRTC client for iOS and Android.
- Connects securely to `wss://sip-api.nexvision.cc/ws`.
- Uses `flutter_webrtc` for media, ICE negotiation, and SDP generation.
- Receives FCM pushed signaling to seamlessly wake up from background/terminated states and handle audio focus natively using `audio_session`.
