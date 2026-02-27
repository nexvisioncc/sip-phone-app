import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../services/background_service.dart';
import '../services/sip_service.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsState {
  final String sipUsername;
  final String sipPassword;
  final String sipDomain;
  final String displayName;
  final String apiUrl;
  final String wsUrl;
  final bool autoRecord;
  final bool runInBackground;
  final bool showIncomingNotification;

  SettingsState({
    this.sipUsername = '',
    this.sipPassword = '',
    this.sipDomain = 'sip.nexvision.cc',
    this.displayName = '',
    this.apiUrl = 'https://sip-api.nexvision.cc',
    this.wsUrl = 'wss://sip-api.nexvision.cc/ws',
    this.autoRecord = false,
    this.runInBackground = false,
    this.showIncomingNotification = true,
  });

  SettingsState copyWith({
    String? sipUsername,
    String? sipPassword,
    String? sipDomain,
    String? displayName,
    String? apiUrl,
    String? wsUrl,
    bool? autoRecord,
    bool? runInBackground,
    bool? showIncomingNotification,
  }) {
    return SettingsState(
      sipUsername: sipUsername ?? this.sipUsername,
      sipPassword: sipPassword ?? this.sipPassword,
      sipDomain: sipDomain ?? this.sipDomain,
      displayName: displayName ?? this.displayName,
      apiUrl: apiUrl ?? this.apiUrl,
      wsUrl: wsUrl ?? this.wsUrl,
      autoRecord: autoRecord ?? this.autoRecord,
      runInBackground: runInBackground ?? this.runInBackground,
      showIncomingNotification: showIncomingNotification ?? this.showIncomingNotification,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(SettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // Migrate: old ws_url pointed directly at Asterisk; now points at the backend
    var wsUrl = prefs.getString('ws_url') ?? 'wss://sip-api.nexvision.cc/ws';
    if (wsUrl.contains('sip-ws.nexvision.cc')) {
      wsUrl = 'wss://sip-api.nexvision.cc/ws';
      await prefs.setString('ws_url', wsUrl);
    }
    state = SettingsState(
      sipUsername: prefs.getString('sip_username') ?? '',
      sipPassword: prefs.getString('sip_password') ?? '',
      sipDomain: prefs.getString('sip_domain') ?? 'sip.nexvision.cc',
      displayName: prefs.getString('display_name') ?? '',
      apiUrl: prefs.getString('api_url') ?? 'https://sip-api.nexvision.cc',
      wsUrl: wsUrl,
      autoRecord: prefs.getBool('auto_record') ?? false,
      runInBackground: prefs.getBool('run_in_background') ?? false,
      showIncomingNotification: prefs.getBool('show_incoming_notification') ?? true,
    );
    // Connect to backend WebSocket on startup with stored credentials
    final username = prefs.getString('sip_username') ?? '';
    final password = prefs.getString('sip_password') ?? '';
    CallService().connect(wsUrl, username: username, password: password);
  }

  Future<void> saveSettings(SettingsState newState) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sip_username', newState.sipUsername);
    await prefs.setString('sip_password', newState.sipPassword);
    await prefs.setString('sip_domain', newState.sipDomain);
    await prefs.setString('display_name', newState.displayName);
    await prefs.setString('api_url', newState.apiUrl);
    await prefs.setString('ws_url', newState.wsUrl);
    await prefs.setBool('auto_record', newState.autoRecord);
    await prefs.setBool('run_in_background', newState.runInBackground);
    await prefs.setBool('show_incoming_notification', newState.showIncomingNotification);
    final oldUsername = state.sipUsername;
    final oldPassword = state.sipPassword;
    final oldWsUrl    = state.wsUrl;
    state = newState;
    // Reconnect when URL or credentials changed, or currently disconnected/authFailed.
    // Always re-auth when credentials change — even if currently "connected" with old creds.
    final credentialsChanged = oldUsername != newState.sipUsername ||
        oldPassword != newState.sipPassword;
    if (oldWsUrl != newState.wsUrl ||
        credentialsChanged ||
        CallService().wsState == WsState.disconnected ||
        CallService().wsState == WsState.authFailed) {
      CallService().connect(newState.wsUrl,
          username: newState.sipUsername, password: newState.sipPassword);
    }
    // Note: do NOT reconnect when wsState == connecting — let the in-progress attempt finish
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  WsState _wsState = WsState.disconnected;

  // Local controllers for credential fields — only saved when "Save & Login" is tapped
  late TextEditingController _usernameCtrl;
  late TextEditingController _passwordCtrl;
  late TextEditingController _displayNameCtrl;
  bool _credentialsDirty = false;

  @override
  void initState() {
    super.initState();
    _wsState = CallService().wsState;
    CallService().onWsStateChanged = _onWsStateChanged;
    final s = ref.read(settingsProvider);
    _usernameCtrl = TextEditingController(text: s.sipUsername);
    _passwordCtrl = TextEditingController(text: s.sipPassword);
    _displayNameCtrl = TextEditingController(text: s.displayName);
  }

  @override
  void dispose() {
    CallService().onWsStateChanged = null;
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  void _onWsStateChanged(WsState state) {
    if (mounted) setState(() => _wsState = state);
  }

  void _saveAndLogin() {
    final settings = ref.read(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    notifier.saveSettings(settings.copyWith(
      sipUsername: _usernameCtrl.text.trim(),
      sipPassword: _passwordCtrl.text,
      displayName: _displayNameCtrl.text.trim(),
    ));
    setState(() => _credentialsDirty = false);
    FocusScope.of(context).unfocus();
  }

  Color get _stateColor {
    switch (_wsState) {
      case WsState.connected:    return Colors.green;
      case WsState.authFailed:   return Colors.red;
      case WsState.disconnected: return Colors.red;
      case WsState.connecting:   return Colors.orange;
    }
  }

  String get _stateLabel {
    switch (_wsState) {
      case WsState.connected:    return 'Connected';
      case WsState.authFailed:   return 'Authentication Failed';
      case WsState.disconnected: return 'Disconnected';
      case WsState.connecting:   return 'Connecting...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Server Settings (top) ────────────────────────────────────────
            _SectionHeader(
              icon: Icons.dns,
              title: 'Server Settings',
              subtitle: 'Advanced: Only change if you know what you\'re doing',
            ),
            const SizedBox(height: 16),
            _SettingsCard(
              children: [
                _TextField(
                  label: 'API URL',
                  hint: 'https://sip-api.nexvision.cc',
                  value: settings.apiUrl,
                  onChanged: (v) => notifier.saveSettings(settings.copyWith(apiUrl: v)),
                ),
                _TextField(
                  label: 'WebSocket URL',
                  hint: 'wss://sip-api.nexvision.cc/ws',
                  value: settings.wsUrl,
                  onChanged: (v) => notifier.saveSettings(settings.copyWith(wsUrl: v)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── SIP Account ──────────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.phone,
              title: 'SIP Account',
              subtitle: 'Your SIP credentials',
            ),
            const SizedBox(height: 16),
            // Connection status indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _stateColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _stateColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: _stateColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _stateLabel,
                    style: TextStyle(
                      color: _stateColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  if (_wsState == WsState.authFailed)
                    TextButton.icon(
                      onPressed: _saveAndLogin,
                      icon: const Icon(Icons.login, size: 16),
                      label: const Text('Login'),
                      style: TextButton.styleFrom(
                        foregroundColor: _stateColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    )
                  else if (_wsState == WsState.disconnected)
                    TextButton.icon(
                      onPressed: () {
                        final s = ref.read(settingsProvider);
                        CallService().connect(s.wsUrl,
                            username: s.sipUsername, password: s.sipPassword);
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reconnect'),
                      style: TextButton.styleFrom(
                        foregroundColor: _stateColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                ],
              ),
            ),
            // Auth error banner
            if (_wsState == WsState.authFailed) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: Colors.red.shade700, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Invalid username or password. Update your credentials and tap Save & Login.',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _SettingsCard(
              children: [
                _ControlledTextField(
                  label: 'SIP Username',
                  hint: 'e.g., herberttung',
                  controller: _usernameCtrl,
                  onChanged: (_) => setState(() => _credentialsDirty = true),
                ),
                _ControlledTextField(
                  label: 'SIP Password',
                  hint: 'Your SIP password',
                  controller: _passwordCtrl,
                  obscureText: true,
                  onChanged: (_) => setState(() => _credentialsDirty = true),
                ),
                _ControlledTextField(
                  label: 'Display Name',
                  hint: 'Name shown to others',
                  controller: _displayNameCtrl,
                  onChanged: (_) => setState(() => _credentialsDirty = true),
                ),
                // Test Connection — placed before Save & Login
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _testConnection(context, settings),
                    icon: const Icon(Icons.network_check, size: 18),
                    label: const Text('Test Connection'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saveAndLogin,
                    icon: const Icon(Icons.login, size: 18),
                    label: Text(_credentialsDirty ? 'Save & Login *' : 'Save & Login'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _credentialsDirty
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Call Recording ───────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.fiber_manual_record,
              title: 'Call Recording',
              subtitle: 'Recordings are saved locally on this device',
            ),
            const SizedBox(height: 16),
            _SettingsCard(
              children: [
                SwitchListTile(
                  title: const Text('Auto-record all calls'),
                  subtitle: const Text('Automatically record incoming & outgoing calls'),
                  value: settings.autoRecord,
                  onChanged: (v) => notifier.saveSettings(settings.copyWith(autoRecord: v)),
                  secondary: Icon(
                    Icons.mic,
                    color: settings.autoRecord ? Colors.red : Colors.grey,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Notifications & Background ───────────────────────────────────
            _SectionHeader(
              icon: Icons.notifications_active,
              title: 'Notifications & Background',
              subtitle: 'Control background behavior and call alerts',
            ),
            const SizedBox(height: 16),
            _SettingsCard(
              children: [
                SwitchListTile(
                  title: const Text('Run in background'),
                  subtitle: const Text('Keep app alive to receive calls when minimized'),
                  value: settings.runInBackground,
                  onChanged: (v) async {
                    await notifier.saveSettings(settings.copyWith(runInBackground: v));
                    if (v) {
                      await BackgroundServiceManager.startService();
                    } else {
                      await BackgroundServiceManager.stopService();
                    }
                  },
                  secondary: Icon(
                    Icons.phone_in_talk,
                    color: settings.runInBackground ? Colors.green : Colors.grey,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Incoming call notifications'),
                  subtitle: const Text('Show popup for incoming calls'),
                  value: settings.showIncomingNotification,
                  onChanged: (v) => notifier.saveSettings(
                    settings.copyWith(showIncomingNotification: v),
                  ),
                  secondary: Icon(
                    Icons.notifications,
                    color: settings.showIncomingNotification ? Colors.blue : Colors.grey,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Quick Setup ──────────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.bolt,
              title: 'Quick Setup',
              subtitle: 'Use preset configurations',
            ),
            const SizedBox(height: 16),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud, color: Colors.blue),
                  title: const Text('Nexvision Cloud'),
                  subtitle: const Text('Use nexvision.cc servers'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    notifier.saveSettings(SettingsState(
                      sipUsername: settings.sipUsername,
                      sipPassword: settings.sipPassword,
                      displayName: settings.displayName,
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nexvision settings applied')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),

            // ── Microphone Test ──────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.mic,
              title: 'Microphone Test',
              subtitle: 'Check if the mic captures audio (same config as calls)',
            ),
            const SizedBox(height: 16),
            const _MicTestCard(),
            const SizedBox(height: 24),

            // Version Info
            Center(
              child: Text(
                'Nexvision SIP Phone v1.0.0',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
    );
  }

  void _testConnection(BuildContext context, SettingsState settings) async {
    // Use credentials from the local controllers (may be unsaved)
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Testing connection...'),
          ],
        ),
      ),
    );

    // Trigger a real reconnect with current credentials and wait up to 8 s
    CallService().connect(settings.wsUrl, username: username, password: password);
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (CallService().wsState == WsState.connecting &&
        DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (!context.mounted) return;
    Navigator.pop(context); // close spinner

    final finalState = CallService().wsState;
    final bool ok = finalState == WsState.connected;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(ok ? Icons.check_circle : Icons.error,
                color: ok ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            Text(ok ? 'Success' : 'Failed'),
          ],
        ),
        content: Text(ok
            ? 'Connected and authenticated successfully.'
            : finalState == WsState.authFailed
                ? 'Authentication failed — wrong username or password.'
                : 'Could not reach the server. Check the WebSocket URL.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: children,
        ),
      ),
    );
  }
}

/// Credential fields — uses a persistent controller so typing doesn't trigger reconnects.
class _ControlledTextField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscureText;
  final ValueChanged<String>? onChanged;

  const _ControlledTextField({
    required this.label,
    required this.hint,
    required this.controller,
    this.obscureText = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        obscureText: obscureText,
        onChanged: onChanged,
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final String label;
  final String hint;
  final String value;
  final bool obscureText;
  final ValueChanged<String> onChanged;

  const _TextField({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: TextEditingController(text: value)
          ..selection = TextSelection.collapsed(offset: value.length),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        obscureText: obscureText,
        onChanged: onChanged,
      ),
    );
  }
}

// ── Mic Test Widget ─────────────────────────────────────────────────────────
class _MicTestCard extends StatefulWidget {
  const _MicTestCard();
  @override
  State<_MicTestCard> createState() => _MicTestCardState();
}

class _MicTestCardState extends State<_MicTestCard> {
  // Device enumeration
  List<MediaDeviceInfo> _devices = [];
  String? _selectedDeviceId; // null = default

  // WebRTC test state
  bool _testing = false;
  double _level = 0.0;
  final List<String> _log = [];
  MediaStream? _stream;
  RTCPeerConnection? _pc;
  RTCPeerConnection? _pc2; // loopback receiver
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _enumerateDevices();
  }

  void _addLog(String msg) {
    if (!mounted) return;
    setState(() {
      _log.add(msg);
      if (_log.length > 30) _log.removeAt(0);
    });
  }

  Future<void> _enumerateDevices() async {
    try {
      // Need permission first before labels are visible
      await Permission.microphone.request();
      final devices = await navigator.mediaDevices.enumerateDevices();
      final inputs = devices.where((d) => d.kind == 'audioinput').toList();
      if (mounted) {
        setState(() => _devices = inputs);
        _addLog('Found ${inputs.length} audio input device(s):');
        for (int i = 0; i < inputs.length; i++) {
          _addLog('  [$i] id=${inputs[i].deviceId} label="${inputs[i].label}"');
        }
      }
    } catch (e) {
      _addLog('enumerateDevices error: $e');
    }
  }

  Future<void> _start() async {
    await _stopInternal();
    setState(() { _testing = true; _level = 0.0; });

    // Each step is individually wrapped so we can log exactly what fails.
    try {
      _addLog('Requesting mic permission...');
      var status = await Permission.microphone.status;
      _addLog('Current status: $status');
      if (!status.isGranted) {
        status = await Permission.microphone.request();
        _addLog('After request: $status');
      }
      if (status.isPermanentlyDenied) {
        _addLog('Permanently denied — opening App Settings...');
        await openAppSettings();
        await _stopInternal();
        return;
      }
      if (!status.isGranted) {
        _addLog('ERROR: mic permission denied');
        await _stopInternal();
        return;
      }
      _addLog('Permission granted OK');
    } catch (e) {
      _addLog('Permission error: $e');
      await _stopInternal();
      return;
    }

    // audio_session: request audio focus from the OS
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
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
      final ok = await session.setActive(true);
      _addLog('AudioSession.setActive=$ok');
    } catch (e) {
      _addLog('AudioSession error (non-fatal): $e');
      // continue anyway
    }

    // Force MODE_IN_COMMUNICATION on Android AudioManager right before getUserMedia.
    // WebRTC.initialize() stores the config but doesn't call setMode() until a call
    // starts. Without this explicit call, AudioRecord captures silence on Samsung.
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
      _addLog('AudioManager mode=IN_COMMUNICATION set');
    } catch (e) {
      _addLog('setAndroidAudioConfig error (non-fatal): $e');
      // continue anyway
    }

    // getUserMedia — disable SW audio processing to bypass Samsung HW AEC conflict
    try {
      final Map<String, dynamic> audioConstraints = {
        'echoCancellation': false,
        'autoGainControl': false,
        'noiseSuppression': false,
        'highpassFilter': false,
      };
      if (_selectedDeviceId != null) {
        audioConstraints['deviceId'] = _selectedDeviceId;
      }
      final label = _selectedDeviceId == null
          ? 'default'
          : (_devices.isEmpty ? _selectedDeviceId : _devices
                .firstWhere((d) => d.deviceId == _selectedDeviceId,
                    orElse: () => _devices.first)
                .label);
      _addLog('getUserMedia device="$label" (processing disabled)');
      _stream = await navigator.mediaDevices.getUserMedia({
        'audio': audioConstraints,
        'video': false,
      });
      final tracks = _stream!.getAudioTracks();
      _addLog('tracks=${tracks.length}');
      for (final t in tracks) {
        _addLog('  id=${t.id} enabled=${t.enabled} muted=${t.muted}');
      }
    } catch (e) {
      _addLog('getUserMedia ERROR: $e');
      await _stopInternal();
      return;
    }

    // Loopback peer connection: PC1 (sender) ↔ PC2 (receiver) connected locally.
    // This forces the full WebRTC audio pipeline (AudioRecord → encoder → ICE) to
    // activate so media-source stats report real audio levels.
    try {
      const pcConfig = {'iceServers': []};
      _pc = await createPeerConnection(pcConfig);
      _pc2 = await createPeerConnection(pcConfig);

      // Wire up ICE candidates between the two PCs
      _pc!.onIceCandidate = (c) {
        if (c != null) _pc2?.addCandidate(c);
      };
      _pc2!.onIceCandidate = (c) {
        if (c != null) _pc?.addCandidate(c);
      };

      // Add audio track to PC1 (sender)
      for (final t in _stream!.getAudioTracks()) {
        await _pc!.addTrack(t, _stream!);
      }

      // Offer/answer exchange (in-process loopback)
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await _pc2!.setRemoteDescription(offer);
      final answer = await _pc2!.createAnswer();
      await _pc2!.setLocalDescription(answer);
      await _pc!.setRemoteDescription(answer);

      _addLog('Loopback PCs created — waiting for ICE...');

      // Wait up to 6s for ICE to connect
      final iceConnected = Completer<void>();
      _pc!.onConnectionState = (s) {
        _addLog('PC state: $s');
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          if (!iceConnected.isCompleted) iceConnected.complete();
        }
      };
      _pc!.onIceConnectionState = (s) {
        _addLog('ICE: $s');
        if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          if (!iceConnected.isCompleted) iceConnected.complete();
        }
      };
      await Future.any([
        iceConnected.future,
        Future.delayed(const Duration(seconds: 6)),
      ]);
      _addLog('ICE done — polling audio...');
    } catch (e) {
      _addLog('PC setup ERROR: $e');
      await _stopInternal();
      return;
    }

    _addLog('Speak now — polling sender.getStats()...');
    int _pollCount = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_pc == null || !mounted) return;
      _pollCount++;
      try {
        final senders = await _pc!.getSenders();
        bool foundSource = false;
        for (final sender in senders) {
          if (sender.track?.kind != 'audio') continue;
          final stats = await sender.getStats();
          for (final r in stats) {
            if (r.type == 'media-source' || r.type == 'audio-source') {
              foundSource = true;
              final raw = r.values['audioLevel'];
              final lvl = raw is num
                  ? raw.toDouble()
                  : double.tryParse(raw?.toString() ?? '') ?? 0.0;
              final dur = r.values['totalSamplesDuration'];
              final energy = r.values['totalAudioEnergy'];
              if (mounted) {
                setState(() => _level = lvl);
                _addLog('level=${lvl.toStringAsFixed(5)} energy=$energy dur=$dur');
              }
            }
            if (r.type == 'outbound-rtp' && _pollCount <= 5) {
              _addLog('tx pkts=${r.values['packetsSent']} bytes=${r.values['bytesSent']}');
            }
            // Log all stat types once (first poll) for diagnostics
            if (_pollCount == 1) {
              _addLog('stat[${r.type}]: ${r.values.keys.take(4).join(',')}');
            }
          }
        }
        if (!foundSource && _pollCount <= 3) {
          _addLog('poll#$_pollCount: no media-source stat found');
        }
      } catch (e) {
        _addLog('stats error: $e');
      }
    });
  }

  Future<void> _stopInternal() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pc2?.close();
    _pc2 = null;
    _pc?.close();
    _pc = null;
    _stream?.dispose();
    _stream = null;
    // Release audio focus
    AudioSession.instance.then((s) => s.setActive(false));
    if (mounted) setState(() { _testing = false; _level = 0.0; });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pc2?.close();
    _pc?.close();
    _stream?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = _level > 0.001;
    final progress = (_level * 20).clamp(0.0, 1.0);
    final barColor = _level > 0.05 ? Colors.green : (_level > 0.001 ? Colors.orange : Colors.red);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device picker
            if (_devices.isNotEmpty) ...[
              const Text('Audio input device:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              DropdownButton<String?>(
                isExpanded: true,
                value: _selectedDeviceId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Default', overflow: TextOverflow.ellipsis)),
                  ..._devices.map((d) => DropdownMenuItem(
                        value: d.deviceId,
                        child: Text(
                          d.label.isNotEmpty ? d.label : d.deviceId,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      )),
                ],
                onChanged: _testing ? null : (v) => setState(() => _selectedDeviceId = v),
              ),
              const SizedBox(height: 8),
            ],

            // Start/Stop
            Row(
              children: [
                Expanded(
                  child: Text(
                    _testing ? 'Speak into the mic...' : 'Select a device and tap Start',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                FilledButton(
                  onPressed: _testing ? _stopInternal : _start,
                  style: FilledButton.styleFrom(
                    backgroundColor: _testing ? Colors.red : Colors.green,
                  ),
                  child: Text(_testing ? 'Stop' : 'Start'),
                ),
              ],
            ),

            if (_testing) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Level: ', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 16,
                        backgroundColor: Colors.grey.shade200,
                        color: barColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_level.toStringAsFixed(5),
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                hasAudio ? '✅ This device captures audio!' : '❌ Silent (level=0)',
                style: TextStyle(
                  color: hasAudio ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],

            // Log
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                height: 160,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ListView.builder(
                  reverse: true,
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Text(
                    _log[_log.length - 1 - i],
                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
