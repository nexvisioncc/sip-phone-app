import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'app.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await WebRTC.initialize(options: {
    'androidAudioConfiguration': AndroidAudioConfiguration.communication.toMap(),
  });
  await BackgroundServiceManager.initialize();
  runApp(
    const ProviderScope(
      child: SipPhoneApp(),
    ),
  );
}
