# SIP Phone App

A native Android SIP phone app built with Flutter, integrated with Twilio SIP trunking.

## Features

- 📞 SIP calling via WebSocket
- 🔔 Push notifications for incoming calls (FCM)
- 📱 Native call UI with CallKit
- 🔊 WebRTC audio handling
- 📋 Call history

## Architecture

```
Flutter App → WebSocket → Kamailio (k8s) → Twilio SIP Trunk
```

## Tech Stack

- **Flutter** - UI framework
- **sip_ua** - SIP signaling
- **flutter_webrtc** - Media handling
- **firebase_messaging** - Push notifications
- **flutter_callkit_incoming** - Native call UI

## Getting Started

### Prerequisites

- Flutter SDK 3.0+
- Android Studio / VS Code
- Firebase project (for push notifications)

### Installation

1. Clone the repository
```bash
git clone https://github.com/nexvisioncc/sip-phone-app.git
cd sip-phone-app/flutter_app
```

2. Install dependencies
```bash
flutter pub get
```

3. Configure Firebase
   - Add your `google-services.json` to `android/app/`
   - Update `lib/config/constants.dart` with your API endpoints

4. Run the app
```bash
flutter run
```

## Building for Release

```bash
flutter build apk --release
```

APK location: `build/app/outputs/flutter-apk/app-release.apk`

## Project Structure

```
lib/
├── config/         # App configuration
├── models/         # Data models
├── services/       # Business logic (SIP, Push, API)
├── providers/      # Riverpod state management
├── screens/        # UI screens
└── widgets/        # Reusable widgets
```

## Backend Infrastructure

See `../docs/k8s-architecture.md` for Kubernetes deployment details.

## License

MIT © Nexvision Limited
