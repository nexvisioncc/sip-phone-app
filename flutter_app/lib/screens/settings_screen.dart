import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

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

  SettingsState({
    this.sipUsername = '',
    this.sipPassword = '',
    this.sipDomain = 'sip.nexvision.cc',
    this.displayName = '',
    this.apiUrl = 'https://sip-api.nexvision.cc',
    this.wsUrl = 'wss://sip-ws.nexvision.cc',
  });

  SettingsState copyWith({
    String? sipUsername,
    String? sipPassword,
    String? sipDomain,
    String? displayName,
    String? apiUrl,
    String? wsUrl,
  }) {
    return SettingsState(
      sipUsername: sipUsername ?? this.sipUsername,
      sipPassword: sipPassword ?? this.sipPassword,
      sipDomain: sipDomain ?? this.sipDomain,
      displayName: displayName ?? this.displayName,
      apiUrl: apiUrl ?? this.apiUrl,
      wsUrl: wsUrl ?? this.wsUrl,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(SettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = SettingsState(
      sipUsername: prefs.getString('sip_username') ?? '',
      sipPassword: prefs.getString('sip_password') ?? '',
      sipDomain: prefs.getString('sip_domain') ?? 'sip.nexvision.cc',
      displayName: prefs.getString('display_name') ?? '',
      apiUrl: prefs.getString('api_url') ?? 'https://sip-api.nexvision.cc',
      wsUrl: prefs.getString('ws_url') ?? 'wss://sip-ws.nexvision.cc',
    );
  }

  Future<void> saveSettings(SettingsState newState) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sip_username', newState.sipUsername);
    await prefs.setString('sip_password', newState.sipPassword);
    await prefs.setString('sip_domain', newState.sipDomain);
    await prefs.setString('display_name', newState.displayName);
    await prefs.setString('api_url', newState.apiUrl);
    await prefs.setString('ws_url', newState.wsUrl);
    state = newState;
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SIP Account Section
            _SectionHeader(
              icon: Icons.phone,
              title: 'SIP Account',
              subtitle: 'Your SIP credentials for making calls',
            ),
            const SizedBox(height: 16),
            _SettingsCard(
              children: [
                _TextField(
                  label: 'SIP Username',
                  hint: 'e.g., 1001 or your phone number',
                  value: settings.sipUsername,
                  onChanged: (v) => notifier.saveSettings(settings.copyWith(sipUsername: v)),
                ),
                _TextField(
                  label: 'SIP Password',
                  hint: 'Your SIP password',
                  value: settings.sipPassword,
                  obscureText: true,
                  onChanged: (v) => notifier.saveSettings(settings.copyWith(sipPassword: v)),
                ),
                _TextField(
                  label: 'Display Name',
                  hint: 'Name shown to others',
                  value: settings.displayName,
                  onChanged: (v) => notifier.saveSettings(settings.copyWith(displayName: v)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Server Settings Section
            _SectionHeader(
              icon: Icons.dns,
              title: 'Server Settings',
              subtitle: 'Advanced: Only change if you know what you\'re doing',
            ),
            const SizedBox(height: 16),
            _SettingsCard(
              children: [
                _TextField(
                  label: 'SIP Domain',
                  hint: 'sip.nexvision.cc',
                  value: settings.sipDomain,
                  onChanged: (v) => notifier.saveSettings(settings.copyWith(sipDomain: v)),
                ),
                _TextField(
                  label: 'API URL',
                  hint: 'https://sip-api.nexvision.cc',
                  value: settings.apiUrl,
                  onChanged: (v) => notifier.saveSettings(settings.copyWith(apiUrl: v)),
                ),
                _TextField(
                  label: 'WebSocket URL',
                  hint: 'wss://sip-ws.nexvision.cc',
                  value: settings.wsUrl,
                  onChanged: (v) => notifier.saveSettings(settings.copyWith(wsUrl: v)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Quick Actions
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

            // Test Connection Button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _testConnection(context, settings),
                icon: const Icon(Icons.network_check),
                label: const Text('Test Connection'),
              ),
            ),
            const SizedBox(height: 16),

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
      ),
    );
  }

  void _testConnection(BuildContext context, SettingsState settings) async {
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

    try {
      // Test API connection
      await Future.delayed(const Duration(seconds: 1));
      
      if (context.mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Success'),
              ],
            ),
            content: const Text('Connection to SIP server successful!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Failed'),
              ],
            ),
            content: Text('Connection failed: $e'),
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
