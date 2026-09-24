import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

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

/// TalkBack names of the symbol keys.
const _kSpoken = {'*': 'Stern', '#': 'Raute'};

/// One reusable dialpad for all call sites (Wählen, in-call DTMF keypad,
/// transfer target). Nachtwache keys: 3 columns, `surface` tiles with
/// radius 22, digit in Bricolage 28/700, letters 10/800 with wide tracking.
/// [keySize] is the key height; keys share the width. Digits scale down
/// instead of overflowing at large system font sizes.
class DialpadGrid extends StatelessWidget {
  const DialpadGrid({super.key, required this.onDigit, this.keySize = 66, this.gap = 10});
  final ValueChanged<String> onDigit;
  final double keySize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (r, row) in _kKeys.indexed) ...[
          if (r > 0) SizedBox(height: gap),
          Row(
            children: [
              for (final (i, key) in row.indexed) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  child: _DialpadKey(
                    label: key,
                    height: keySize,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onDigit(key);
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _DialpadKey extends StatelessWidget {
  const _DialpadKey({required this.label, required this.height, required this.onTap});
  final String label;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final letters = _kLetters[label];
    final radius = BorderRadius.circular(height >= 60 ? 22 : 18);
    return Semantics(
      button: true,
      label: _kSpoken[label] ?? label,
      // excludeSemantics drops the InkWell's action, so TalkBack needs it here.
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: NwType.display(28, weight: FontWeight.w700).copyWith(color: c.text, height: 1.05)),
                    if (letters == null)
                      const SizedBox(height: 12)
                    else
                      Text(
                        letters,
                        style: TextStyle(
                          fontFamily: NwFonts.ui,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: c.faint,
                          height: 1.2,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
