// API Configuration
class ApiConfig {
  static const String baseUrl = 'https://sip-api.nexvision.cc';
  // WebSocket endpoint on the backend — handles SIP bridging to Asterisk
  static const String wsUrl = 'wss://sip-api.nexvision.cc/ws';
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
}

// Firebase Configuration
class FirebaseConfig {
  static const String vapidKey = 'YOUR_VAPID_KEY';
}

// Storage Keys
class StorageKeys {
  static const String sipUsername = 'sip_username';
  static const String sipPassword = 'sip_password';
  static const String fcmToken = 'fcm_token';
  static const String userId = 'user_id';
}
