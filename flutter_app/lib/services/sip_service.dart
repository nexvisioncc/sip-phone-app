import 'package:sip_ua/sip_ua.dart';
import 'package:logger/logger.dart';
import '../config/constants.dart';

class SipService implements SipUaHelperListener {
  // Singleton — all screens share the same instance and the same SIP connection
  static final SipService _instance = SipService._internal();
  factory SipService() => _instance;
  SipService._internal();

  final SIPUAHelper _helper = SIPUAHelper();
  final Logger _logger = Logger();

  Call? _activeCall;
  bool _isMuted = false;

  Function(CallState)? onCallStateChanged;
  Function(RegistrationState)? onRegistrationStateChanged;

  SIPUAHelper get helper => _helper;

  Future<void> register({
    required String username,
    required String password,
  }) async {
    _helper.stop();
    final settings = UaSettings()
      ..webSocketUrl = SipConfig.websocketUrl
      ..uri = 'sip:$username@${SipConfig.domain}'
      ..authorizationUser = username
      ..password = password
      ..displayName = username
      ..userAgent = SipConfig.userAgent
      ..register_expires = SipConfig.registerExpires;

    _logger.i('Registering SIP user: $username');
    _helper.removeSipUaHelperListener(this);
    _helper.addSipUaHelperListener(this);
    _helper.start(settings);
  }
  
  void unregister() {
    _logger.i('Unregistering SIP');
    _helper.stop();
  }
  
  void call(String number) {
    final target = 'sip:$number@${SipConfig.domain}';
    _logger.i('Calling: $target');
    _helper.call(target, voiceonly: true);
  }
  
  void hangup() {
    _logger.i('Hanging up');
    _helper.terminateSessions({});
  }

  void toggleMute() {
    if (_activeCall != null) {
      _isMuted = !_isMuted;
      _activeCall!.mute(_isMuted);
    }
  }

  void toggleSpeaker() {
    // Implemented via webrtc_service
  }

  void sendDTMF(String tone) {
    if (_activeCall != null) {
      _activeCall!.sendDTMF(tone);
    }
  }
  
  // SipUaHelperListener implementations
  @override
  void registrationStateChanged(RegistrationState state) {
    _logger.i('Registration state: ${state.state}');
    onRegistrationStateChanged?.call(state);
  }
  
  @override
  void callStateChanged(Call call, CallState state) {
    _logger.i('Call state: ${state.state}');
    if (state.state == CallStateEnum.ENDED || state.state == CallStateEnum.FAILED) {
      _activeCall = null;
      _isMuted = false;
    } else {
      _activeCall = call;
    }
    onCallStateChanged?.call(state);
  }
  
  @override
  void transportStateChanged(TransportState state) {
    _logger.i('Transport state: ${state.state}');
  }
  
  @override
  void onNewMessage(SIPMessageRequest msg) {
    _logger.i('New message: ${msg.message}');
  }
  
  @override
  void onNewNotify(Notify ntf) {
    _logger.i('New notify: $ntf');
  }
}
