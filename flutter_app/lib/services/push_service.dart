import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'api_service.dart';
import 'sip_service.dart';

class PushService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final ApiService _api = ApiService();
  final Logger _logger = Logger();
  
  Function(String callId, String callerName, String callerNumber)? onIncomingCall;
  
  Future<void> initialize() async {
    _logger.i('Initializing push service');

    // POST_NOTIFICATIONS — dangerous runtime permission required on Android 13+
    // Must be granted so the incoming call notification can appear when app is closed.
    if (await Permission.notification.isDenied) {
      final status = await Permission.notification.request();
      _logger.i('Notification permission: $status');
      if (status.isPermanentlyDenied) {
        _logger.w('Notification permission permanently denied — opening settings');
        await openAppSettings();
      }
    }

    // USE_FULL_SCREEN_INTENT — required for full-screen call screen on locked device.
    // On Android 14+ this must be explicitly granted by the user.
    final canFullScreen = await FlutterCallkitIncoming.canUseFullScreenIntent();
    if (!canFullScreen) {
      _logger.i('Requesting USE_FULL_SCREEN_INTENT permission');
      await FlutterCallkitIncoming.requestFullIntentPermission();
    }

    // FCM permission (covers iOS; on Android POST_NOTIFICATIONS above handles it)
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
    // Respect the user's notification preference
    final prefs = await SharedPreferences.getInstance();
    final showNotification = prefs.getBool('show_incoming_notification') ?? true;
    if (!showNotification) return;

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
  
  void _handleCallKitEvent(CallEvent? event) {
    if (event == null) return;

    switch (event.event) {
      case Event.actionCallAccept:
        _logger.i('Call accepted via popup');
        // Do NOT call endCall() here — calling endCall() on a ringing call
        // asynchronously fires actionCallDecline, which calls reject() while
        // answer() is still in progress, closing _pc and causing an NPE crash.
        CallService().answer();
        break;
      case Event.actionCallDecline:
        _logger.i('Call declined via popup');
        // Only reject if the decline event's callId matches our current pending
        // call. endAllCalls() fires actionCallDecline for any still-ringing
        // CallKit notification, and the resulting stale event must not reject
        // a subsequent new call that arrived after the old call ended.
        try {
          final body = event.body;
          if (body is Map) {
            final declinedId = body['id']?.toString() ?? '';
            if (declinedId.isNotEmpty &&
                declinedId == CallService().pendingCallId &&
                !CallService().isAnswering) {
              CallService().reject();
            } else {
              _logger.i('Ignoring stale decline for $declinedId (pending=${CallService().pendingCallId})');
            }
          }
        } catch (e) {
          _logger.e('CallKit decline body error: $e');
        }
        break;
      case Event.actionCallEnded:
        _logger.i('Call ended');
        break;
      default:
        break;
    }
  }
}

// Background handler - must be top-level, runs in a separate isolate.
// Registered in main() BEFORE runApp() so the callback handle is stored
// in shared prefs and survives app termination.
@pragma('vm:entry-point')
Future<void> handleBackgroundFcmMessage(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  if (message.data['type'] == 'incoming_call') {
    final params = CallKitParams(
      id: message.data['call_id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      nameCaller: message.data['caller_name'] ?? 'Unknown',
      appName: 'Nexvision SIP',
      handle: message.data['caller_number'] ?? '',
      type: 0,
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
        actionColor: '#4CAF50',
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }
}
