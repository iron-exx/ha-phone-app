import 'package:flutter/material.dart';

const _kKeys = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['*', '0', '#'],
];

/// One reusable dialpad grid for all three call sites the old native app
/// had (outgoing dial, in-call DTMF keypad, blind-transfer target entry) --
/// matches the "one component, three call sites" pattern the project's own
/// planning docs called out for DialpadComposable.
class DialpadGrid extends StatelessWidget {
  const DialpadGrid({super.key, required this.onDigit});
  final ValueChanged<String> onDigit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _kKeys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final key in row)
                  _DialpadKey(label: key, onTap: () => onDigit(key)),
              ],
            ),
          ),
      ],
    );
  }
}

class _DialpadKey extends StatelessWidget {
  const _DialpadKey({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Text(label, style: Theme.of(context).textTheme.headlineSmall),
      ),
    );
  }
}
