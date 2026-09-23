import 'package:flutter/material.dart';

import '../services/call_launcher.dart';
import '../theme/app_colors.dart';
import 'dialpad_grid.dart';
import 'round_action_button.dart';

/// Number display + dialpad + green call button. Used by the Tastatur tab
/// and the standalone '/dialpad' route.
class DialerView extends StatefulWidget {
  const DialerView({super.key});

  @override
  State<DialerView> createState() => _DialerViewState();
}

class _DialerViewState extends State<DialerView> {
  String _digits = '';

  /// Wahlwiederholung like on a desk phone: call with an empty field brings back the last number.
  static String _lastDialed = '';

  void _append(String d) => setState(() => _digits += d);

  void _backspace() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Future<void> _call() async {
    final number = _digits;
    if (number.isEmpty) {
      if (_lastDialed.isNotEmpty) setState(() => _digits = _lastDialed);
      return;
    }
    _lastDialed = number;
    setState(() => _digits = '');
    await CallLauncher.call(context, number);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Shrink keys on small screens so the call button stays visible.
        final keySize = (constraints.maxHeight / 8.5).clamp(56.0, 76.0);
        return Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _digits.isEmpty ? 'Nummer eingeben' : _digits,
                      key: const Key('dialer-display'),
                      style: tabular(theme.textTheme.displaySmall)?.copyWith(
                        color: _digits.isEmpty ? theme.colorScheme.onSurfaceVariant : null,
                        fontSize: _digits.isEmpty ? 24 : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: DialpadGrid(onDigit: _append, keySize: keySize),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  SizedBox(width: keySize),
                  CallButton(
                    key: const Key('dialer-call'),
                    color: AppColors.answer,
                    icon: Icons.call,
                    tooltip: 'Anrufen',
                    // Empty field + call = Wahlwiederholung (fills in the last number).
                    onPressed: _digits.isEmpty && _lastDialed.isEmpty ? null : _call,
                  ),
                  SizedBox(
                    width: keySize,
                    child: _digits.isEmpty
                        ? null
                        // IconButton has no long-press and its tooltip would
                        // swallow one, hence a plain InkResponse.
                        : Semantics(
                            button: true,
                            label: 'Löschen, lang drücken löscht alles',
                            child: InkResponse(
                              key: const Key('dialer-backspace'),
                              radius: 28,
                              onTap: _backspace,
                              onLongPress: () => setState(() => _digits = ''),
                              child: SizedBox(
                                height: keySize,
                                child: const Icon(Icons.backspace_outlined, size: 28),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
