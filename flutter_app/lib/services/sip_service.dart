import 'dart:async';
import 'dart:convert';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/constants.dart';
import 'api_service.dart';

/// Connection state of the WebSocket link to the backend.
enum WsState { disconnected, connecting, connected, authFailed }

/// State of the current call leg.
enum ActiveCallState { connecting, ringing, active, ended }

/// Data about an incoming call received from the backend.
class IncomingCallInfo {
  final String callId;
  final String from;
  final String sdpOffer;
  const IncomingCallInfo({
    required this.callId,
    required this.from,
    required this.sdpOffer,
  });
}

/// CallService replaces the old SipService.
/// It connects to the backend WebSocket (wss://sip-api.nexvision.cc/ws),
/// receives incoming call events with an SDP offer from Asterisk,
/// creates a WebRTC peer connection, and bridges the audio.
class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  final Logger _log = Logger();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  String? _wsUrl;
  String _wsUsername = '';
  String _wsPassword = '';
  bool _disposed = false;

  WsState _wsState = WsState.disconnected;
  IncomingCallInfo? _pendingCall;
  String? _activeCallId;
  String? _answeringCallId; // set during answer() setup, cleared when active or cleaned up
  bool _isMuted = false;
  bool _isAnswering = false;
  bool _remoteDescSet = false; // prevent double setRemoteDescription on outgoing calls
  String? _pendingAcceptCallId; // set when user accepted via CallKit before WS delivered incoming_call

  // ── Callbacks ────────────────────────────────────────────────────────────
  Function(WsState)? onWsStateChanged;
  Function(IncomingCallInfo)? onIncomingCall;
  Function(String callId, ActiveCallState state)? onCallStateChanged;

  WsState get wsState => _wsState;
  bool get isMuted => _isMuted;
  bool get isAnswering => _isAnswering;
  bool get hasPendingCall => _pendingCall != null;
  String? get pendingCallId => _pendingCall?.callId;
  String? get activeCallId => _activeCallId;

  // ── Debug ─────────────────────────────────────────────────────────────────
  final List<String> debugLog = [];
  Function(String)? onDebugLine;
  Timer? _statsTimer;

  void _dbg(String line) {
    final ts = DateTime.now().toLocal().toString().substring(11, 23);
    final msg = '[$ts] $line';
    _log.i(msg);
    debugLog.add(msg);
    if (debugLog.length > 60) debugLog.removeAt(0);
    onDebugLine?.call(msg);
  }

  // ── Connect / Reconnect ──────────────────────────────────────────────────
  void connect(String wsUrl, {String username = '', String password = ''}) {
    _wsUrl = wsUrl;
    _wsUsername = username;
    _wsPassword = password;
    _doDisconnect();
    _setWsState(WsState.connecting);
    _log.i('[CallService] Connecting to $wsUrl');
    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        connectTimeout: const Duration(seconds: 10),
      );
      _sub = _channel!.stream.listen(
        _onMessage,
        onDone: _onClosed,
        onError: (_) => _onClosed(),
      );
      // Send credentials immediately — backend requires auth as first message
      _send({'type': 'auth', 'username': _wsUsername, 'password': _wsPassword});
    } catch (e) {
      _log.e('[CallService] Connect error: $e');
      _scheduleReconnect();
    }
  }

  void _doDisconnect() {
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _onClosed() {
    _log.w('[CallService] WS closed');
    // Don't overwrite authFailed — user must fix credentials before reconnecting
    if (_wsState != WsState.authFailed) {
      _setWsState(WsState.disconnected);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    Future.delayed(const Duration(seconds: 5), () {
      if (_wsState == WsState.disconnected && _wsUrl != null) {
        connect(_wsUrl!, username: _wsUsername, password: _wsPassword);
      }
    });
  }

  void _setWsState(WsState s) {
    _wsState = s;
    onWsStateChanged?.call(s);
  }

  // Re-send FCM token to backend on every WS connect (token survives pod restarts)
  void _reRegisterFcmToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(StorageKeys.fcmToken);
    if (token != null && token.isNotEmpty) {
      ApiService().registerDevice(token).catchError((_) {});
      _log.i('[CallService] FCM token re-registered with backend');
    }
  }

  // ── Incoming messages from backend ───────────────────────────────────────
  void _onMessage(dynamic data) {
    try {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      switch (msg['type'] as String?) {
        case 'auth_ok':
          _dbg('[Auth] Authentication successful');
          break;
        case 'auth_failed':
          _dbg('[Auth] Authentication failed: ${msg['reason']}');
          _setWsState(WsState.authFailed);
          _doDisconnect();
          break;
        case 'registered':
          _setWsState(WsState.connected);
          _reRegisterFcmToken();
          break;
        case 'incoming_call':
          _pendingCall = IncomingCallInfo(
            callId: msg['call_id'] as String,
            from: msg['from'] as String,
            sdpOffer: msg['sdp_offer'] as String,
          );
          _dbg('incoming_call: ${_pendingCall!.callId} from=${_pendingCall!.from} hasCallback=${onIncomingCall != null}');
          onIncomingCall?.call(_pendingCall!);
          // Auto-answer if user already accepted via CallKit before WS delivered this
          if (_pendingAcceptCallId != null) {
            _pendingAcceptCallId = null;
            _dbg('auto-answering deferred CallKit accept');
            answer();
          }
          break;
        case 'call_state':
          _handleCallStateMsg(msg);
          break;
        case 'error':
          _log.w('[CallService] Backend error: ${msg['message']}');
          break;
      }
    } catch (e) {
      _log.e('[CallService] Message parse error: $e');
    }
  }

  void _handleCallStateMsg(Map<String, dynamic> msg) {
    final state = msg['state'] as String?;
    final callId = msg['call_id'] as String? ?? _activeCallId ?? '';
    if (state == 'dialing' || state == 'connecting') {
      _activeCallId = callId;
      onCallStateChanged?.call(callId, ActiveCallState.connecting);
    } else if (state == 'ringing') {
      _activeCallId = callId;
      // 183 Session Progress carries Asterisk's SDP (ICE + DTLS).
      // Set remote description immediately so ICE starts while the phone rings.
      final earlySdp = msg['sdp_answer'] as String?;
      if (earlySdp != null && earlySdp.isNotEmpty && _pc != null && !_remoteDescSet) {
        _remoteDescSet = true;
        _pc!.setRemoteDescription(RTCSessionDescription(earlySdp, 'answer'))
            .then((_) => _dbg('Remote desc set from early SDP (183)'))
            .catchError((e) => _dbg('setRemoteDescription (183) error: $e'));
      }
      onCallStateChanged?.call(callId, ActiveCallState.ringing);
    } else if (state == 'active') {
      _activeCallId = callId;
      // For outgoing calls: set remote description only if 183 didn't already do it.
      // Double-calling setRemoteDescription(answer) when state is already 'stable'
      // is invalid per WebRTC spec and silently corrupts ICE state.
      final sdpAnswer = msg['sdp_answer'] as String?;
      if (sdpAnswer != null && sdpAnswer.isNotEmpty && _pc != null && !_remoteDescSet) {
        _remoteDescSet = true;
        _pc!.setRemoteDescription(RTCSessionDescription(sdpAnswer, 'answer'))
          .then((_) => _dbg('Remote desc set from 200 OK SDP answer'))
          .catchError((e) => _dbg('setRemoteDescription error: $e'));
      } else if (_remoteDescSet) {
        _dbg('Remote desc already set from 183 — skipping 200 OK SDP');
      }
      onCallStateChanged?.call(callId, ActiveCallState.active);
      // Poll RTP stats every 2 s
      _statsTimer?.cancel();
      _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollStats());
    } else if (state == 'ended' || state == 'failed') {
      final id = _activeCallId ?? callId;
      _activeCallId = null;
      _pendingCall = null;
      _cleanupPc();
      onCallStateChanged?.call(id, ActiveCallState.ended);
    }
  }

  void _send(Map<String, dynamic> obj) {
    _channel?.sink.add(jsonEncode(obj));
  }

  // ── Answer incoming call ─────────────────────────────────────────────────
  Future<void> answer() async {
    if (_isAnswering) {
      _dbg('answer() already in progress — ignoring duplicate');
      return;
    }
    final call = _pendingCall;
    if (call == null) {
      // WS hasn't delivered incoming_call yet (app just woke from background).
      // Store the intent and auto-answer when incoming_call arrives.
      _dbg('answer() — no pending call yet, deferring accept');
      _pendingAcceptCallId = 'pending';
      Future.delayed(const Duration(seconds: 20), () => _pendingAcceptCallId = null);
      return;
    }
    _isAnswering = true;
    _answeringCallId = call.callId; // track call ID during setup so hangup() can send BYE
    _pendingCall = null; // Clear immediately — 30s CallKit timeout must not reject active call
    _dbg('answer() start — callId=${call.callId}');
    onCallStateChanged?.call(call.callId, ActiveCallState.connecting);

    try {
      // 1) OS-level audio focus via audio_session plugin.
      //    Calls AudioManager.requestAudioFocus() on Android.
      final audioSession = await AudioSession.instance;
      await audioSession.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      final activated = await audioSession.setActive(true);
      _dbg('AudioSession: activated=$activated');

      // Force MODE_IN_COMMUNICATION before getUserMedia.
      // WebRTC.initialize() stores the config but doesn't call AudioManager.setMode()
      // until a call starts. Without this, AudioRecord captures silence on Samsung.
      try {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration(
            manageAudioFocus: false, // audio_session already holds focus
            androidAudioMode: AndroidAudioMode.inCommunication,
            androidAudioFocusMode: AndroidAudioFocusMode.gain,
            androidAudioStreamType: AndroidAudioStreamType.voiceCall,
            androidAudioAttributesUsageType:
                AndroidAudioAttributesUsageType.voiceCommunication,
            androidAudioAttributesContentType:
                AndroidAudioAttributesContentType.speech,
            forceHandleAudioRouting: true,
          ),
        );
        _dbg('AudioManager: MODE_IN_COMMUNICATION set');
      } catch (e) {
        _dbg('setAndroidAudioConfig error (non-fatal): $e');
      }

      _pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {
            'urls': 'turn:172.93.53.224:3478',
            'username': 'nexvision',
            'credential': 'turn_secret_2024',
          },
        ],
      });

      _pc!.onIceConnectionState = (s) => _dbg('ICE: $s');
      _pc!.onConnectionState = (s) => _dbg('PC: $s');
      _pc!.onSignalingState = (s) => _dbg('Sig: $s');

      // Set remote description FIRST so tracks are associated with the right m-lines
      await _pc!.setRemoteDescription(
        RTCSessionDescription(call.sdpOffer, 'offer'),
      );

      // Log offer direction lines
      for (final line in call.sdpOffer.split('\n')) {
        if (line.startsWith('a=sendrecv') || line.startsWith('a=sendonly') ||
            line.startsWith('a=recvonly') || line.startsWith('a=inactive') ||
            line.startsWith('m=audio')) {
          _dbg('OFFER SDP: ${line.trim()}');
        }
      }

      // Request microphone permission before getUserMedia
      final micStatus = await Permission.microphone.request();
      _dbg('Mic permission: $micStatus');
      if (!micStatus.isGranted) {
        reject();
        return;
      }

      // Prime the audio pipeline BEFORE acquiring the real stream.
      // _primeAudioPipeline uses its own internal getUserMedia stream so that
      // closing the loopback PCs can never affect the real _localStream tracks.
      // On Samsung (and some other Android), AudioRecord stays dormant until a
      // peer connection actually connects. The loopback (no network needed)
      // forces it active in ~1-2s so the real stream opens with a warm pipeline.
      await _primeAudioPipeline();

      // Get microphone and add track AFTER setRemoteDescription
      // (required for flutter_webrtc to emit a=sendrecv instead of a=recvonly)
      // Disable SW audio processing — Samsung HW AEC conflicts with WebRTC's SW
      // processing and silences the mic. With all processing off, AudioRecord
      // captures real audio and flutter_sound can also record without silence.
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': false,
          'autoGainControl': false,
          'noiseSuppression': false,
          'highpassFilter': false,
        },
        'video': false,
      });

      final tracks = _localStream!.getAudioTracks();
      _dbg('getUserMedia: ${tracks.length} audio track(s)');
      for (final t in tracks) {
        _dbg('  track id=${t.id} enabled=${t.enabled} muted=${t.muted} kind=${t.kind}');
      }

      for (final track in tracks) {
        await _pc!.addTrack(track, _localStream!);
      }
      _dbg('addTrack done');

      // Create and set local answer
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);

      // Log answer direction lines
      if (answer.sdp != null) {
        for (final line in answer.sdp!.split('\n')) {
          if (line.startsWith('a=sendrecv') || line.startsWith('a=sendonly') ||
              line.startsWith('a=recvonly') || line.startsWith('a=inactive') ||
              line.startsWith('m=audio')) {
            _dbg('ANSWER SDP: ${line.trim()}');
          }
        }
      }

      // Wait for ICE gathering (max 5 s)
      final sdpAnswer = await _waitForIce();
      _dbg('ICE gathered — sending answer (${sdpAnswer.length} bytes SDP)');

      // Abort if hangup() was called while ICE was gathering
      if (_answeringCallId == null) {
        _dbg('answer() aborted — hangup called during setup, sending reject');
        _send({'type': 'reject', 'call_id': call.callId});
        _cleanupPc();
        return;
      }

      _send({
        'type': 'answer',
        'call_id': call.callId,
        'sdp_answer': sdpAnswer,
      });
      _activeCallId = call.callId;
      _answeringCallId = null;

      // Poll RTP stats every 2 s to confirm audio packets are being sent
      _statsTimer?.cancel();
      _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollStats());
    } catch (e) {
      _dbg('answer() ERROR: $e');
      // _pendingCall was cleared above, so use local `call` variable directly
      _send({'type': 'reject', 'call_id': call.callId});
      _cleanupPc();
    } finally {
      _isAnswering = false;
    }
  }

  Future<void> _pollStats() async {
    if (_pc == null) return;
    try {
      final stats = await _pc!.getStats();
      for (final report in stats) {
        if (report.type == 'outbound-rtp') {
          final v = report.values;
          _dbg('TX → pkts=${v['packetsSent']} bytes=${v['bytesSent']} codec=${v['codecId']}');
        }
        if (report.type == 'media-source' || report.type == 'audio-source') {
          final v = report.values;
          final level = v['audioLevel'];
          if (level != null) _dbg('MIC level=$level totalEnergy=${v['totalAudioEnergy']}');
        }
      }
    } catch (_) {}
  }

  // Creates a local loopback (PC1 sender ↔ PC2 receiver) using its OWN internal
  // getUserMedia stream. Local ICE connects in ~1-2s, which forces Android's
  // AudioRecord pipeline to fully activate. The temp stream and PCs are disposed
  // after — the real _localStream is acquired separately after this returns.
  Future<void> _primeAudioPipeline() async {
    _dbg('priming audio pipeline...');
    RTCPeerConnection? pc1, pc2;
    MediaStream? primeStream;
    try {
      primeStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': false,
          'autoGainControl': false,
          'noiseSuppression': false,
          'highpassFilter': false,
        },
        'video': false,
      });

      const cfg = {'iceServers': <Map>[]};
      pc1 = await createPeerConnection(cfg);
      pc2 = await createPeerConnection(cfg);

      pc1.onIceCandidate = (c) { if (c != null) pc2?.addCandidate(c); };
      pc2.onIceCandidate = (c) { if (c != null) pc1?.addCandidate(c); };

      for (final t in primeStream.getAudioTracks()) {
        await pc1.addTrack(t, primeStream);
      }

      final offer = await pc1.createOffer();
      await pc1.setLocalDescription(offer);
      await pc2.setRemoteDescription(offer);
      final answer = await pc2.createAnswer();
      await pc2.setLocalDescription(answer);
      await pc1.setRemoteDescription(answer);

      final connected = Completer<void>();
      pc1.onIceConnectionState = (s) {
        if ((s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
             s == RTCIceConnectionState.RTCIceConnectionStateCompleted) &&
            !connected.isCompleted) {
          connected.complete();
        }
      };
      await Future.any([connected.future, Future.delayed(const Duration(seconds: 3))]);
      _dbg('audio pipeline primed');
    } catch (e) {
      _dbg('primeAudio error (non-fatal): $e');
    } finally {
      await pc1?.close();
      await pc2?.close();
      primeStream?.dispose();
    }
  }

  /// Strips all non-audio m-sections from [sdp] and fixes a=group:BUNDLE.
  ///
  /// Asterisk's pjsip WebSocket transport has a small receive buffer; a full
  /// WebRTC SDP with video ICE candidates (~6600 bytes) triggers
  /// PJSIP_ERXOVERFLOW.  Removing the video section drops the SDP to ~2000
  /// bytes.  Also removes video mids from a=group:BUNDLE so the SDP is valid.
  String _audioOnlySdp(String sdp) {
    final lines = sdp.split('\n');

    // Collect mid values of non-audio m-sections so we can fix BUNDLE
    final removedMids = <String>[];
    bool inNonAudio = false;
    for (final line in lines) {
      final t = line.trim();
      if (t.startsWith('m=')) inNonAudio = !t.startsWith('m=audio');
      if (inNonAudio && t.startsWith('a=mid:')) {
        removedMids.add(t.substring(6).trim());
      }
    }

    // Re-build keeping only session section + audio m-section
    final result = <String>[];
    bool skipSection = false;
    for (final line in lines) {
      final t = line.trim();
      if (t.startsWith('m=')) skipSection = !t.startsWith('m=audio');
      if (skipSection) continue;

      // Fix a=group:BUNDLE by removing the video mids
      if (t.startsWith('a=group:BUNDLE') && removedMids.isNotEmpty) {
        var fixed = t;
        for (final mid in removedMids) {
          fixed = fixed.replaceAll(' $mid', '');
        }
        result.add(line.startsWith('\r') ? fixed : fixed);
        continue;
      }

      result.add(line);
    }
    return result.join('\n');
  }

  Future<String> _waitForIce() {
    final c = Completer<String>();

    Future<void> resolve() async {
      final desc = await _pc!.getLocalDescription();
      if (!c.isCompleted) c.complete(desc?.sdp ?? '');
    }

    _pc!.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate != null && candidate.candidate != null) {
        _dbg('ICE cand: ${candidate.candidate}');
      }
    };

    _pc!.onIceGatheringState = (state) {
      _dbg('ICE gather: $state');
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        resolve();
      }
    };
    // Fallback timeout — increased to 8s to allow TURN relay allocation
    Future.delayed(const Duration(seconds: 8), resolve);
    return c.future;
  }

  // ── Initiate outgoing call ───────────────────────────────────────────────
  Future<void> call(String number) async {
    _dbg('call() start — number=$number wsState=$_wsState');

    // Wait up to 10 s for the WS to become connected (handles the race where
    // the user taps Call just before the scheduled reconnect fires).
    if (_wsState != WsState.connected) {
      _dbg('call() — WS not connected, waiting up to 10 s…');
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (_wsState != WsState.connected &&
             _wsState != WsState.authFailed &&
             DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (_wsState != WsState.connected) {
        _dbg('call() — timed out waiting for WS; aborting');
        // Trigger ended so CallScreen pops back to dialer
        final callId = DateTime.now().millisecondsSinceEpoch.toString();
        onCallStateChanged?.call(callId, ActiveCallState.ended);
        return;
      }
      _dbg('call() — WS now connected, proceeding');
    }

    try {
      // Audio session
      final audioSession = await AudioSession.instance;
      await audioSession.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      await audioSession.setActive(true);

      try {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration(
            manageAudioFocus: false,
            androidAudioMode: AndroidAudioMode.inCommunication,
            androidAudioFocusMode: AndroidAudioFocusMode.gain,
            androidAudioStreamType: AndroidAudioStreamType.voiceCall,
            androidAudioAttributesUsageType:
                AndroidAudioAttributesUsageType.voiceCommunication,
            androidAudioAttributesContentType:
                AndroidAudioAttributesContentType.speech,
            forceHandleAudioRouting: true,
          ),
        );
      } catch (e) {
        _dbg('setAndroidAudioConfig error (non-fatal): $e');
      }

      // Mic permission
      final micStatus = await Permission.microphone.request();
      _dbg('Mic permission: $micStatus');
      if (!micStatus.isGranted) {
        _dbg('call() — mic denied');
        return;
      }

      // Prime audio pipeline (warms up AudioRecord on Samsung)
      await _primeAudioPipeline();

      _pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {
            'urls': 'turn:172.93.53.224:3478',
            'username': 'nexvision',
            'credential': 'turn_secret_2024',
          },
        ],
      });

      _pc!.onIceConnectionState = (s) => _dbg('ICE: $s');
      _pc!.onConnectionState    = (s) => _dbg('PC: $s');
      _pc!.onSignalingState     = (s) => _dbg('Sig: $s');

      // Get mic and add track (before createOffer so SDP includes audio m-line)
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': false,
          'autoGainControl': false,
          'noiseSuppression': false,
          'highpassFilter': false,
        },
        'video': false,
      });

      for (final track in _localStream!.getAudioTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
      _dbg('call() — mic tracks added: ${_localStream!.getAudioTracks().length}');

      // Create WebRTC offer — audio only so the remote answer m-line order matches.
      // Without OfferToReceiveVideo:false, libwebrtc adds a video m-line even
      // with no video tracks added, causing setRemoteDescription to fail when
      // Asterisk answers with only an audio m-line.
      final offer = await _pc!.createOffer({
        'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': false},
      });
      await _pc!.setLocalDescription(offer);

      // Wait for ICE gathering (max 8 s to allow TURN relay allocation)
      final rawSdp = await _waitForIce();
      final sdpOffer = _audioOnlySdp(rawSdp); // safety strip in case any non-audio slips through
      _dbg('call() — ICE gathered (${rawSdp.length} → ${sdpOffer.length} bytes)');

      // Generate a call ID and send to backend
      final callId = DateTime.now().millisecondsSinceEpoch.toString();
      _activeCallId = callId;
      onCallStateChanged?.call(callId, ActiveCallState.connecting);

      _send({
        'type': 'call',
        'number': number,
        'sdp_offer': sdpOffer,
        'call_id': callId,
      });
    } catch (e) {
      _dbg('call() ERROR: $e');
      _cleanupPc();
    }
  }

  // ── Reject / Hangup ──────────────────────────────────────────────────────
  void reject() {
    final cid = _pendingCall?.callId;
    if (cid == null) return;
    _send({'type': 'reject', 'call_id': cid});
    _pendingCall = null;
    _cleanupPc();
  }

  void hangup() {
    final cid = _activeCallId ?? _answeringCallId ?? _pendingCall?.callId;
    if (cid == null) return;
    _send({'type': 'hangup', 'call_id': cid});
    _activeCallId = null;
    _answeringCallId = null; // signal answer() to abort if still running
    _pendingCall = null;
    _cleanupPc();
  }

  // ── In-call controls ─────────────────────────────────────────────────────
  void toggleMute() {
    _isMuted = !_isMuted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !_isMuted);
  }

  void sendDTMF(String tone) {
    final cid = _activeCallId;
    if (cid == null) return;
    _send({'type': 'dtmf', 'call_id': cid, 'tone': tone});
  }

  // ── Cleanup ──────────────────────────────────────────────────────────────
  void _cleanupPc() {
    _isMuted = false;
    _remoteDescSet = false;
    _answeringCallId = null; // signal answer() to abort if still running
    _statsTimer?.cancel();
    _statsTimer = null;
    _localStream?.dispose();
    _localStream = null;
    _pc?.close();
    _pc = null;
    // Release audio focus so other apps can resume audio
    AudioSession.instance.then((s) => s.setActive(false));
  }
}
