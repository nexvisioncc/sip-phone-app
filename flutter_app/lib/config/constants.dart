// API Configuration
class ApiConfig {
  static const String baseUrl = 'https://sip-api.nexvision.cc';
  static const String wsUrl = 'wss://sip-ws.nexvision.cc';
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
}

// SIP Configuration
class SipConfig {
  static const String domain = 'sip.nexvision.cc';
  static const String websocketUrl = 'wss://sip-ws.nexvision.cc';
  static const int registerExpires = 300;
  static const String userAgent = 'Nexvision SIP Phone/1.0';
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
