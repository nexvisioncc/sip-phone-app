import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sip_service.dart';
import 'call_screen.dart';

final dialedNumberProvider = StateNotifierProvider<DialedNumberNotifier, String>((ref) {
  return DialedNumberNotifier();
});

class DialedNumberNotifier extends StateNotifier<String> {
  DialedNumberNotifier() : super('');
  
  void add(String digit) {
    if (state.length < 15) {
      state = state + digit;
    }
  }
  
  void backspace() {
    if (state.isNotEmpty) {
      state = state.substring(0, state.length - 1);
    }
  }
  
  void clear() {
    state = '';
  }
}

class DialerScreen extends ConsumerWidget {
  const DialerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final number = ref.watch(dialedNumberProvider);
    final sipService = SipService();

    return Column(
        children: [
          // Number display
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            child: Text(
              number.isEmpty ? 'Enter number' : number,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: number.isEmpty ? Colors.grey : null,
              ),
            ),
          ),
          
          // Backspace button
          if (number.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 32),
                child: IconButton(
                  icon: const Icon(Icons.backspace, color: Colors.grey),
                  onPressed: () => ref.read(dialedNumberProvider.notifier).backspace(),
                ),
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Numpad
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GridView.count(
                crossAxisCount: 3,
                childAspectRatio: 1.2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  _NumpadButton(
                    digit: '1',
                    subtext: '',
                    onPressed: () => ref.read(dialedNumberProvider.notifier).add('1'),
                  ),
                  _NumpadButton(
                    digit: '2',
                    subtext: 'ABC',
                    onPressed: () => ref.read(dialedNumberProvider.notifier).add('2'),
                  ),
                  _NumpadButton(
                    digit: '3',
                    subtext: 'DEF',
                    onPressed: () => ref.read(dialedNumberProvider.notifier).add('3'),
                  ),
                  _NumpadButton(
                    digit: '4',
                    subtext: 'GHI',
                    onPressed: () => ref.read(dialedNumberProvider.notifier).add('4'),
                  ),
                  _NumpadButton(
                    digit: '5',
                    subtext: 'JKL',
                    onPressed: () => ref.read(dialedNumberProvider.notifier).add('5'),
                  ),
                  _NumpadButton(
                    digit: '6',
                    subtext: 'MNO',
                    onPressed: () => ref.read(dialedNumberProvider.notifier).add('6'),
                  ),
                  _NumpadButton(
                    digit: '7',
                    subtext: 'PQRS',
                    onPressed: () => ref.read(dialedNumberProvider.notifier).add('7'),
                  ),
                  _NumpadButton(
                    digit: '8',
                    subtext: 'TUV',
                    onPressed: () => ref.read(dialedNumberProvider.notifier).add('8'),
                  ),
                  _NumpadButton(
                    digit: '9',
                    subtext: 'WXYZ',
                    onPressed: () => ref.read(dialedNumberProvider.notifier).add('9'),
                  ),
                  _NumpadButton(
                    digit: '*',
                    subtext: '',
                    onPressed: () => ref.read(dialedNumberProvider.notifier).add('*'),
                  ),
                  _NumpadButton(
                    digit: '0',
                    subtext: '+',
                    onPressed: () => ref.read(dialedNumberProvider.notifier).add('0'),
                  ),
                  _NumpadButton(
                    digit: '#',
                    subtext: '',
                    onPressed: () => ref.read(dialedNumberProvider.notifier).add('#'),
                  ),
                ],
              ),
            ),
          ),
          
          // Call button
          Padding(
            padding: const EdgeInsets.all(24),
            child: FloatingActionButton.large(
              onPressed: number.isNotEmpty
                ? () {
                    sipService.call(number);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CallScreen(number: number),
                      ),
                    );
                  }
                : null,
              backgroundColor: Colors.green,
              child: const Icon(Icons.call, size: 32),
            ),
          ),
        ],
    );
  }
}

class _NumpadButton extends StatelessWidget {
  final String digit;
  final String subtext;
  final VoidCallback onPressed;

  const _NumpadButton({
    required this.digit,
    required this.subtext,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              digit,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtext.isNotEmpty)
              Text(
                subtext,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
