import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sip_service.dart';
import '../services/recording_service.dart';
import '../screens/settings_screen.dart';
import '../screens/recents_screen.dart';
import 'package:uuid/uuid.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String number;
  final bool isIncoming;

  const CallScreen({super.key, required this.number, this.isIncoming = false});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  final CallService _callService = CallService();
  final RecordingService _recordingService = RecordingService();

  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _isRecording = false;
  bool _isEnding = false;
  bool _isWaitingToAccept = false;
  bool _showDebug = false;
  String _callStatus = 'Calling...';
  Duration _callDuration = Duration.zero;
  Timer? _callTimer;
  String? _callId;
  final List<String> _debugLines = [];

  @override
  void initState() {
    super.initState();
    _callService.onCallStateChanged = _handleCallStateChanged;
    _debugLines.addAll(_callService.debugLog);
    _callService.onDebugLine = (line) {
      if (mounted) setState(() {
        _debugLines.add(line);
        if (_debugLines.length > 60) _debugLines.removeAt(0);
      });
    };
    if (widget.isIncoming) {
      if (_callService.isAnswering) {
        // Already answering via CallKit accept — skip the waiting state
        _callStatus = 'Connecting...';
        _isWaitingToAccept = false;
      } else {
        _callStatus = 'Incoming Call';
        _isWaitingToAccept = true;
      }
    }
    // Auto-dismiss if no state event arrives within 35 s (e.g. network drop)
    Future.delayed(const Duration(seconds: 35), () {
      if (mounted && _isWaitingToAccept) _handleCallEnded();
    });
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _callService.onCallStateChanged = null;
    _callService.onDebugLine = null;
    super.dispose();
  }

  void _handleCallStateChanged(String callId, ActiveCallState state) {
    if (!mounted) return;
    setState(() {
      switch (state) {
        case ActiveCallState.connecting:
          _callStatus = 'Connecting...';
          _isWaitingToAccept = false;
          break;
        case ActiveCallState.active:
          _callStatus = 'Connected';
          _isWaitingToAccept = false;
          _startCallTimer();
          _maybeAutoRecord();
          break;
        case ActiveCallState.ended:
          _callStatus = 'Ended';
          _isWaitingToAccept = false;
          _handleCallEnded();
          break;
      }
    });
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDuration += const Duration(seconds: 1));
    });
  }

  void _maybeAutoRecord() {
    final settings = ref.read(settingsProvider);
    if (settings.autoRecord) _startRecording();
  }

  Future<void> _startRecording() async {
    _callId = const Uuid().v4();
    await _recordingService.startRecording(_callId!);
    if (mounted) setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    await _recordingService.stopRecording(
      number: widget.number,
      isIncoming: widget.isIncoming,
    );
    if (mounted) setState(() => _isRecording = false);
    ref.invalidate(recordingsProvider);
  }

  void _handleCallEnded() {
    if (_isEnding) return;
    _isEnding = true;
    _callTimer?.cancel();
    if (_isRecording) _stopRecording();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _callService.toggleMute();
  }

  void _toggleSpeaker() {
    setState(() => _isSpeaker = !_isSpeaker);
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _accept() async {
    // Do NOT call endAllCalls() here — it asynchronously fires actionCallDecline
    // which calls reject() while answer() is running, closing _pc mid-flight.
    setState(() {
      _callStatus = 'Connecting...';
      _isWaitingToAccept = false;
    });
    await _callService.answer();
  }

  void _hangup() {
    FlutterCallkitIncoming.endAllCalls();
    setState(() => _isWaitingToAccept = false);
    _callService.hangup();
    _handleCallEnded();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Column(
          children: [
            // Recording indicator
            if (_isRecording)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _BlinkingDot(),
                    const SizedBox(width: 6),
                    Text(
                      'Recording',
                      style: TextStyle(
                        color: Colors.red.shade300,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            const Spacer(),

            // Caller info
            Column(
              children: [
                const CircleAvatar(
                  radius: 60,
                  backgroundColor: Color(0xFF6366F1),
                  child: Icon(Icons.person, size: 60, color: Colors.white),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.number,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _callStatus,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                  ),
                ),
                if (_callDuration.inSeconds > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${_callDuration.inMinutes.toString().padLeft(2, '0')}:${(_callDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),

            const Spacer(),

            // Call controls
            if (_isWaitingToAccept) ...[
              // Incoming call: Accept / Reject
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallControlButton(
                      icon: Icons.call_end,
                      label: 'Reject',
                      onPressed: _hangup,
                      backgroundColor: Colors.red,
                      size: 70,
                    ),
                    _CallControlButton(
                      icon: Icons.call,
                      label: 'Accept',
                      onPressed: _accept,
                      backgroundColor: Colors.green,
                      size: 70,
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Active call: mute, end, speaker
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallControlButton(
                      icon: _isMuted ? Icons.mic_off : Icons.mic,
                      label: _isMuted ? 'Unmute' : 'Mute',
                      onPressed: _toggleMute,
                      isActive: _isMuted,
                    ),
                    _CallControlButton(
                      icon: Icons.call_end,
                      label: 'End',
                      onPressed: _hangup,
                      backgroundColor: Colors.red,
                      size: 70,
                    ),
                    _CallControlButton(
                      icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
                      label: _isSpeaker ? 'Speaker' : 'Earpiece',
                      onPressed: _toggleSpeaker,
                      isActive: _isSpeaker,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Record button
              _CallControlButton(
                icon: _isRecording ? Icons.stop : Icons.fiber_manual_record,
                label: _isRecording ? 'Stop Rec' : 'Record',
                onPressed: _toggleRecording,
                backgroundColor: _isRecording ? Colors.red.shade700 : null,
                isActive: _isRecording,
              ),

              const SizedBox(height: 24),

              // DTMF numpad
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'])
                      _DTMFButton(
                        digit: digit,
                        onPressed: () => _callService.sendDTMF(digit),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Debug toggle
            GestureDetector(
              onTap: () => setState(() => _showDebug = !_showDebug),
              child: Text(
                _showDebug ? 'Hide debug ▲' : 'Debug ▼',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
              ),
            ),

            if (_showDebug)
              Container(
                height: 180,
                margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ListView.builder(
                  reverse: true,
                  itemCount: _debugLines.length,
                  itemBuilder: (_, i) => Text(
                    _debugLines[_debugLines.length - 1 - i],
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 9, fontFamily: 'monospace'),
                  ),
                ),
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// Blinking red dot for recording indicator
class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();
  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final double size;
  final bool isActive;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.backgroundColor,
    this.size = 56,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FloatingActionButton(
          onPressed: onPressed,
          heroTag: null,
          backgroundColor: backgroundColor ?? (isActive ? Colors.white : Colors.white24),
          foregroundColor: backgroundColor != null ? Colors.white : (isActive ? Colors.black : Colors.white),
          elevation: 0,
          mini: size < 60,
          child: Icon(icon, size: size > 60 ? 32 : 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _DTMFButton extends StatelessWidget {
  final String digit;
  final VoidCallback onPressed;

  const _DTMFButton({required this.digit, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.1),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          child: Text(
            digit,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
