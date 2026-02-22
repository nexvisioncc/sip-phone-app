# Flutter App Architecture

## Project Structure

```
sip_phone_app/
├── android/                    # Android-specific config
├── ios/                        # iOS config (if needed later)
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── config/
│   │   ├── constants.dart      # API endpoints, SIP settings
│   │   └── routes.dart         # Navigation routes
│   ├── models/
│   │   ├── user.dart
│   │   ├── call.dart
│   │   └── sip_account.dart
│   ├── services/
│   │   ├── sip_service.dart    # SIP registration/calls
│   │   ├── push_service.dart   # FCM handling
│   │   ├── api_service.dart    # REST API client
│   │   └── webrtc_service.dart # Media handling
│   ├── providers/
│   │   ├── auth_provider.dart
│   │   ├── call_provider.dart
│   │   └── settings_provider.dart
│   ├── screens/
│   │   ├── splash_screen.dart
│   │   ├── login_screen.dart
│   │   ├── dialer_screen.dart
│   │   ├── call_screen.dart
│   │   ├── contacts_screen.dart
│   │   └── settings_screen.dart
│   ├── widgets/
│   │   ├── call_button.dart
│   │   ├── numpad.dart
│   │   ├── call_controls.dart
│   │   └── incoming_call_dialog.dart
│   └── utils/
│       ├── permissions.dart
│       ├── audio_manager.dart
│       └── helpers.dart
├── test/
└── pubspec.yaml
```

## pubspec.yaml

```yaml
name: sip_phone_app
description: SIP Phone App for Nexvision

publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  
  # SIP & WebRTC
  flutter_sip: ^0.5.0
  flutter_webrtc: ^0.9.47
  sip_ua: ^0.6.0  # Alternative pure Dart SIP
  
  # Push Notifications
  firebase_core: ^2.24.2
  firebase_messaging: ^14.7.10
  flutter_callkit_incoming: ^2.0.0
  
  # State Management
  flutter_riverpod: ^2.4.9
  
  # Networking
  dio: ^5.4.0
  web_socket_channel: ^2.4.0
  
  # Storage
  shared_preferences: ^2.2.2
  flutter_secure_storage: ^9.0.0
  
  # UI
  flutter_screenutil: ^5.9.0
  google_fonts: ^6.1.0
  flutter_svg: ^2.0.9
  
  # Permissions
  permission_handler: ^11.1.0
  
  # Audio
  audio_session: ^0.1.18
  flutter_sound: ^9.2.13
  
  # Utils
  uuid: ^4.2.2
  intl: ^0.18.1
  logger: ^2.0.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.1

flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/sounds/
```

## Core Services

### SIP Service

```dart
// lib/services/sip_service.dart
import 'package:sip_ua/sip_ua.dart';

class SipService implements SipUaHelperListener {
  final SIPUAHelper _helper = SIPUAHelper();
  
  Future<void> register({
    required String username,
    required String password,
    required String domain,
  }) async {
    final settings = UaSettings()
      ..webSocketUrl = 'wss://sip-ws.nexvision.cc:5062'
      ..uri = 'sip:$username@$domain'
      ..authorizationUser = username
      ..password = password
      ..displayName = username
      ..userAgent = 'Nexvision SIP Phone/1.0'
      ..register_expires = 300;
    
    _helper.start(settings);
    _helper.addSipUaHelperListener(this);
  }
  
  void call(String number) {
    _helper.call('sip:$number@twilio.com', voiceonly: true);
  }
  
  void hangup() {
    _helper.terminateSessions();
  }
  
  // Implement SipUaHelperListener methods...
  @override
  void registrationStateChanged(RegistrationState state) {
    // Handle registration state
  }
  
  @override
  void callStateChanged(Call call, CallState state) {
    // Handle call state changes
  }
  
  @override
  void transportStateChanged(TransportState state) {}
  
  @override
  void onNewMessage(SIPMessageRequest msg) {}
}
```

### Push Notification Service

```dart
// lib/services/push_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class PushService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  
  Future<void> initialize() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    
    // Get FCM token
    final token = await _fcm.getToken();
    print('FCM Token: $token');
    // Send token to your API
    
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Handle background/terminated messages
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
  }
  
  void _handleForegroundMessage(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'incoming_call') {
      _showIncomingCall(data);
    }
  }
  
  Future<void> _showIncomingCall(Map<String, dynamic> data) async {
    final params = CallKitParams(
      id: data['call_id'],
      nameCaller: data['caller_name'] ?? 'Unknown',
      appName: 'Nexvision SIP',
      avatar: data['caller_avatar'],
      handle: data['caller_number'],
      type: 0, // Audio call
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
    );
    
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }
}

// Background handler must be top-level
@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  // Handle push when app is terminated
  // Register SIP and wait for INVITE
}
```

### API Service

```dart
// lib/services/api_service.dart
import 'package:dio/dio.dart';

class ApiService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://sip-api.nexvision.cc',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
  
  Future<void> registerDevice({
    required String userId,
    required String fcmToken,
    required String sipUsername,
  }) async {
    await _dio.post('/devices', data: {
      'user_id': userId,
      'fcm_token': fcmToken,
      'sip_username': sipUsername,
      'platform': 'android',
    });
  }
  
  Future<Map<String, dynamic>> getSipCredentials(String userId) async {
    final response = await _dio.get('/users/$userId/sip-credentials');
    return response.data;
  }
}
```

## Screens

### Dialer Screen

```dart
// lib/screens/dialer_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DialerScreen extends ConsumerWidget {
  const DialerScreen({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final number = ref.watch(dialedNumberProvider);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Nexvision SIP')),
      body: Column(
        children: [
          // Number display
          Container(
            padding: const EdgeInsets.all(32),
            child: Text(
              number,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          
          // Numpad
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 1.5,
              children: [
                for (final digit in ['1', '2', '3', '4', '5', '6', 
                                     '7', '8', '9', '*', '0', '#'])
                  _NumpadButton(
                    digit: digit,
                    onPressed: () => ref.read(dialedNumberProvider.notifier).add(digit),
                  ),
              ],
            ),
          ),
          
          // Call button
          Padding(
            padding: const EdgeInsets.all(24),
            child: FloatingActionButton.large(
              onPressed: number.isNotEmpty 
                ? () => ref.read(sipServiceProvider).call(number)
                : null,
              backgroundColor: Colors.green,
              child: const Icon(Icons.call),
            ),
          ),
        ],
      ),
    );
  }
}
```

### Call Screen

```dart
// lib/screens/call_screen.dart
class CallScreen extends ConsumerWidget {
  const CallScreen({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callStateProvider);
    
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            
            // Caller info
            Column(
              children: [
                const CircleAvatar(
                  radius: 60,
                  child: Icon(Icons.person, size: 60),
                ),
                const SizedBox(height: 24),
                Text(
                  callState.remoteDisplayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  callState.statusText,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            
            const Spacer(),
            
            // Call controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CallButton(
                  icon: Icons.mic_off,
                  onPressed: () => ref.read(sipServiceProvider).toggleMute(),
                ),
                _CallButton(
                  icon: Icons.call_end,
                  color: Colors.red,
                  size: 70,
                  onPressed: () => ref.read(sipServiceProvider).hangup(),
                ),
                _CallButton(
                  icon: Icons.volume_up,
                  onPressed: () => ref.read(sipServiceProvider).toggleSpeaker(),
                ),
              ],
            ),
            
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
```

## Android Configuration

### AndroidManifest.xml

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    
    <!-- Permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.DISABLE_KEYGUARD" />
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    
    <application
        android:label="Nexvision SIP"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize"
            android:showWhenLocked="true"
            android:turnScreenOn="true">
            
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
                
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        
        <!-- Firebase Messaging Service -->
        <service
            android:name="com.google.firebase.messaging.FirebaseMessagingService"
            android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT" />
            </intent-filter>
        </service>
        
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
```

## Build & Distribute

```bash
# Build APK for sideloading
flutter build apk --release

# Output: build/app/outputs/flutter-apk/app-release.apk

# Install on device
adb install build/app/outputs/flutter-apk/app-release.apk

# Or host for download
# Upload to https://releases.nexvision.cc/sip-phone/
```
