import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

/// Entry point for the background isolate — must be top-level.
@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) {
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'Nexvision SIP',
      content: 'Running in background — ready for calls',
    );
  }

  service.on('stop').listen((_) {
    service.stopSelf();
  });
}

class BackgroundServiceManager {
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onBackgroundServiceStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'nexvision_sip_bg',
        initialNotificationTitle: 'Nexvision SIP',
        initialNotificationContent: 'Running in background — ready for calls',
        foregroundServiceNotificationId: 7777,
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  static Future<void> startService() async {
    final service = FlutterBackgroundService();
    await service.startService();
  }

  static Future<void> stopService() async {
    final service = FlutterBackgroundService();
    service.invoke('stop');
  }

  static Future<bool> isRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }
}
