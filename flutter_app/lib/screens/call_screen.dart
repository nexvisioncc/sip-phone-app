import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sip_ua/sip_ua.dart';
import '../services/sip_service.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String number;
  
  const CallScreen({super.key, required this.number});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  final SipService _sipService = SipService();
  bool _isMuted = false;
  bool _isSpeaker = false;
  String _callStatus = 'Calling...';
  Duration _callDuration = Duration.zero;
  
  @override
  void initState() {
    super.initState();
    _sipService.onCallStateChanged = _handleCallStateChanged;
  }
  
  void _handleCallStateChanged(CallState state) {
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
          break;
        case CallStateEnum.ENDED:
          _callStatus = 'Ended';
          Navigator.of(context).pop();
          break;
        case CallStateEnum.FAILED:
          _callStatus = 'Failed';
          break;
        default:
          break;
      }
    });
  }
  
  void _startCallTimer() {
    // Start timer for call duration
  }
  
  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _sipService.toggleMute();
  }
  
  void _toggleSpeaker() {
    setState(() {
      _isSpeaker = !_isSpeaker;
    });
    // Toggle speaker via webrtc
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
            const Spacer(),
            
            // Caller info
            Column(
              children: [
                const CircleAvatar(
                  radius: 60,
                  backgroundColor: Color(0xFF6366F1),
                  child: Icon(
                    Icons.person,
                    size: 60,
                    color: Colors.white,
                  ),
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
            
            const SizedBox(height: 48),
            
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

  const _DTMFButton({
    required this.digit,
    required this.onPressed,
  });

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
