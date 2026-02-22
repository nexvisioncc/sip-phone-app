# SIP Phone App - Build Instructions

## Prerequisites

- Flutter SDK 3.0+ (https://docs.flutter.dev/get-started/install)
- Android Studio or VS Code
- Android device or emulator

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/nexvisioncc/sip-phone-app.git
cd sip-phone-app/flutter_app
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Configure Firebase (Already Done)

The `google-services.json` is already included in the repository for the Nexvision project.

### 4. Build Debug APK

```bash
flutter build apk --debug
```

APK location: `build/app/outputs/flutter-apk/app-debug.apk`

### 5. Install on Device

```bash
# Connect your Android device via USB
# Enable USB debugging on your device
adb install build/app/outputs/flutter-apk/app-debug.apk
```

Or manually copy the APK to your device and install it.

## Configuration

### First Time Setup

1. Open the app
2. Tap the **Settings** icon (gear) in the top right
3. Enter your SIP credentials:
   - **SIP Username**: Your extension or phone number
   - **SIP Password**: Your SIP password
   - **Display Name**: Name shown to others when you call
4. Tap **Test Connection** to verify

### Default Server Settings

The app is pre-configured for Nexvision infrastructure:
- **SIP Domain**: `sip.nexvision.cc`
- **API URL**: `https://sip-api.nexvision.cc`
- **WebSocket URL**: `wss://sip-ws.nexvision.cc`

### Getting SIP Credentials

Contact your administrator for SIP account credentials, or use the test account:
- Username: `test-user`
- Password: `test-pass`

## Testing

### Test Push Notifications

1. Get your device's FCM token from the logs
2. Use the API to send a test push:

```bash
curl -X POST https://sip-api.nexvision.cc/push/send \
  -H "Content-Type: application/json" \
  -d '{
    "token": "YOUR_DEVICE_FCM_TOKEN",
    "title": "Test Call",
    "body": "Incoming call from Test",
    "data": {
      "type": "incoming_call",
      "call_id": "12345",
      "caller_name": "Test User",
      "caller_number": "+1234567890"
    }
  }'
```

### Test SIP Calling

1. Register with your SIP credentials
2. Dial a number on the dialer screen
3. Tap the green call button

## Building Release APK

```bash
flutter build apk --release
```

APK location: `build/app/outputs/flutter-apk/app-release.apk`

## Troubleshooting

### App crashes on startup
- Check that `google-services.json` exists in `android/app/`
- Run `flutter clean` and `flutter pub get` again

### Can't connect to SIP server
- Verify your SIP credentials in Settings
- Check that your device has internet access
- Test the API: `curl https://sip-api.nexvision.cc/health`

### Push notifications not working
- Ensure Firebase is properly configured
- Check device notification permissions
- Verify FCM token is registered

## Development

### Project Structure
```
lib/
├── config/         # Configuration constants
├── models/         # Data models
├── providers/      # Riverpod state management
├── screens/        # UI screens
│   ├── dialer_screen.dart
│   ├── call_screen.dart
│   ├── settings_screen.dart
│   └── splash_screen.dart
├── services/       # Business logic
│   ├── sip_service.dart
│   ├── push_service.dart
│   └── api_service.dart
└── main.dart
```

### Running in Debug Mode

```bash
flutter run
```

This will hot-reload on code changes.

## Support

For issues or questions, contact Nexvision support.
