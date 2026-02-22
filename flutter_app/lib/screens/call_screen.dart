import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:uuid/uuid.dart';
import '../services/sip_service.dart';
import '../services/recording_service.dart';
import '../screens/settings_screen.dart';
import '../screens/recents_screen.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String number;
  final bool isIncoming;

  const CallScreen({super.key, required this.number, this.isIncoming = false});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  final SipService _sipService = SipService();
  final RecordingService _recordingService = RecordingService();

  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _isRecording = false;
  String _callStatus = 'Calling...';
  Duration _callDuration = Duration.zero;
  Timer? _callTimer;
  String? _callId;

  @override
  void initState() {
    super.initState();
    _sipService.onCallStateChanged = _handleCallStateChanged;
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleCallStateChanged(CallState state) async {
    if (!mounted) return;
    setState(() {
      switch (state.state) {
        case CallStateEnum.CALL_INITIATION:
          _callStatus = 'Calling...';
          break;
        case CallStateEnum.PROGRESS:
          _callStatus = 'Ringing...';
          break;
        case CallStateEnum.ACCEPTED:
          _callStatus = 'Connected';
          _startCallTimer();
          _maybeAutoRecord();
          break;
        case CallStateEnum.ENDED:
          _callStatus = 'Ended';
          _handleCallEnded();
          break;
        case CallStateEnum.FAILED:
          _callStatus = 'Failed';
          _handleCallEnded();
          break;
        default:
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
    if (settings.autoRecord) {
      _startRecording();
    }
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
    _callTimer?.cancel();
    if (_isRecording) _stopRecording();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _sipService.toggleMute();
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

  void _hangup() {
    _sipService.hangup();
    Navigator.of(context).pop();
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

            // Call controls — row 1: mute, end, speaker
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

            // Row 2: record button
            _CallControlButton(
              icon: _isRecording ? Icons.stop : Icons.fiber_manual_record,
              label: _isRecording ? 'Stop Rec' : 'Record',
              onPressed: _toggleRecording,
              backgroundColor: _isRecording ? Colors.red.shade700 : null,
              isActive: _isRecording,
            ),

            const SizedBox(height: 24),

            // Numpad for DTMF
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
                      onPressed: () => _sipService.sendDTMF(digit),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 48),
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
