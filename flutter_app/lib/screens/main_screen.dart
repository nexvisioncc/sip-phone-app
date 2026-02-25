import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sip_service.dart';
import 'dialer_screen.dart';
import 'recents_screen.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';
import 'call_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;
  bool _callScreenActive = false;

  static const _titles = ['Nexvision SIP', 'Recent Calls', 'Contacts', 'Settings'];

  @override
  void initState() {
    super.initState();
    CallService().onIncomingCall = _handleIncomingCall;
  }

  @override
  void dispose() {
    CallService().onIncomingCall = null;
    super.dispose();
  }

  void _handleIncomingCall(IncomingCallInfo callInfo) {
    // Guard: ignore retransmitted events while a call screen is already active
    if (_callScreenActive) return;

    if (mounted) {
      _callScreenActive = true;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CallScreen(number: callInfo.from, isIncoming: true),
      )).whenComplete(() => _callScreenActive = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          DialerScreen(),
          RecentsScreen(),
          ContactsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dialpad_outlined),
            selectedIcon: Icon(Icons.dialpad),
            label: 'Keypad',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Recents',
          ),
          NavigationDestination(
            icon: Icon(Icons.contacts_outlined),
            selectedIcon: Icon(Icons.contacts),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
