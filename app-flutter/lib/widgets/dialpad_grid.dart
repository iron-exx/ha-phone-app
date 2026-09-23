import 'package:flutter/material.dart';

const _kKeys = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['*', '0', '#'],
];

const _kLetters = {
  '2': 'ABC',
  '3': 'DEF',
  '4': 'GHI',
  '5': 'JKL',
  '6': 'MNO',
  '7': 'PQRS',
  '8': 'TUV',
  '9': 'WXYZ',
  '0': '+',
};

/// One reusable dialpad grid for all three call sites the old native app
/// had (outgoing dial, in-call DTMF keypad, blind-transfer target entry) --
/// matches the "one component, three call sites" pattern the project's own
/// planning docs called out for DialpadComposable.
class DialpadGrid extends StatelessWidget {
  const DialpadGrid({super.key, required this.onDigit, this.keySize = 72});
  final ValueChanged<String> onDigit;
  final double keySize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _kKeys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final key in row)
                  _DialpadKey(label: key, size: keySize, onTap: () => onDigit(key)),
              ],
            ),
          ),
      ],
    );
  }
}

class _DialpadKey extends StatelessWidget {
  const _DialpadKey({required this.label, required this.size, required this.onTap});
  final String label;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final letters = _kLetters[label];
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (letters != null)
                Text(
                  letters,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 1.2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
