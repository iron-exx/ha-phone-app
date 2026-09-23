import 'package:flutter/material.dart';

import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import 'dialpad_grid.dart';

/// DTMF keypad during a call; shows the digits sent so far.
class InCallKeypadSheet extends StatefulWidget {
  const InCallKeypadSheet({super.key});

  @override
  State<InCallKeypadSheet> createState() => _InCallKeypadSheetState();
}

class _InCallKeypadSheetState extends State<InCallKeypadSheet> {
  String _sent = '';

  void _send(String d) {
    setState(() => _sent += d);
    SipChannel.instance.sendDtmf(d).catchError((Object e) {
      debugPrint('sendDtmf failed: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _sent.isEmpty ? 'Tastatur' : _sent,
              style: tabular(Theme.of(context).textTheme.headlineSmall),
            ),
            const SizedBox(height: 16),
            DialpadGrid(onDigit: _send, keySize: 64),
          ],
        ),
      ),
    );
  }
}
