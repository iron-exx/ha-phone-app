import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'dialpad_grid.dart';

/// Blind-transfer target entry (SIP REFER).
class TransferSheet extends StatefulWidget {
  const TransferSheet({super.key, required this.onTransfer});
  final ValueChanged<String> onTransfer;

  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  String _target = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Weiterleiten an', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: Text(
                    _target.isEmpty ? 'Nummer eingeben' : _target,
                    textAlign: TextAlign.center,
                    style: tabular(theme.textTheme.headlineSmall),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: _target.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Löschen',
                          icon: const Icon(Icons.backspace_outlined),
                          onPressed: () =>
                              setState(() => _target = _target.substring(0, _target.length - 1)),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DialpadGrid(onDigit: (d) => setState(() => _target += d), keySize: 60),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.phone_forwarded),
              onPressed: _target.isEmpty ? null : () => widget.onTransfer(_target),
              label: const Text('Weiterleiten'),
            ),
          ],
        ),
      ),
    );
  }
}
