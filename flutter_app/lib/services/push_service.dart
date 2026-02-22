import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'api_service.dart';

class PushService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final ApiService _api = ApiService();
  final Logger _logger = Logger();
  
  Function(String callId, String callerName, String callerNumber)? onIncomingCall;
  
  Future<void> initialize() async {
    _logger.i('Initializing push service');
    
    // Request permissions
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    _logger.i('FCM permission: ${settings.authorizationStatus}');
    
    // Get and save FCM token
    final token = await _fcm.getToken();
    _logger.i('FCM Token: $token');
    
    if (token != null) {
      await _saveToken(token);
      await _api.registerDevice(token);
    }
    
    // Listen for token refresh
    _fcm.onTokenRefresh.listen((newToken) async {
      _logger.i('FCM Token refreshed: $newToken');
      await _saveToken(newToken);
      await _api.registerDevice(newToken);
    });
    
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Handle background/terminated messages
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
    
    // Handle call kit events
    FlutterCallkitIncoming.onEvent.listen((event) {
      _handleCallKitEvent(event);
    });
  }
  
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.fcmToken, token);
  }
  
  void _handleForegroundMessage(RemoteMessage message) {
    _logger.i('Foreground message: ${message.messageId}');
    final data = message.data;
    
    if (data['type'] == 'incoming_call') {
      _showIncomingCall(data);
    }
  }
  
  Future<void> _showIncomingCall(Map<String, dynamic> data) async {
    final params = CallKitParams(
      id: data['call_id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      nameCaller: data['caller_name'] ?? 'Unknown',
      appName: 'Nexvision SIP',
      avatar: data['caller_avatar'],
      handle: data['caller_number'] ?? '',
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
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#6366F1',
        backgroundUrl: 'assets/images/background.png',
        actionColor: '#4CAF50',
      ),
    );
    
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }
  
  void _handleCallKitEvent(dynamic event) {
    if (event == null) return;
    
    switch (event.event) {
      case 'ACCEPT':
        _logger.i('Call accepted');
        // Trigger SIP registration and answer
        onIncomingCall?.call(
          event.body['id'],
          event.body['nameCaller'],
          event.body['handle'],
        );
        break;
      case 'DECLINE':
        _logger.i('Call declined');
        break;
      case 'ENDED':
        _logger.i('Call ended');
        break;
    }
  }
}

// Background handler - must be top-level
@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  // Handle push when app is terminated
  // This wakes the app and should trigger SIP registration
}
