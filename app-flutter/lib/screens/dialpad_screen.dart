import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/call_events.dart';
import '../services/sip_channel.dart';
import '../widgets/dialpad_grid.dart';

/// Replaces the old native OutgoingCallActivity. Placing a call here is
/// Phase 1's actual demo milestone: a real SIP INVITE through the
/// unmodified PJSIP stack, triggered from Dart via SipChannel.makeCall,
/// which on the native side re-homes CallRegistration.reportOutgoingCall's
/// Report-First glue (see SipChannelHandler.kt).
class DialpadScreen extends StatefulWidget {
  const DialpadScreen({super.key});

  @override
  State<DialpadScreen> createState() => _DialpadScreenState();
}

class _DialpadScreenState extends State<DialpadScreen> {
  String _digits = '';

  Future<void> _call() async {
    if (_digits.isEmpty) return;
    if (!await Permission.microphone.request().isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Mikrofon-Berechtigung wird zum Telefonieren benötigt.'),
        ));
      }
      return;
    }
    CallEvents.instance.lastDisconnected = null;
    await SipChannel.instance.makeCall(_digits);
    if (mounted) Navigator.of(context).pushReplacementNamed('/active-call');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anrufen')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              _digits.isEmpty ? 'Nebenstelle eingeben' : _digits,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            DialpadGrid(onDigit: (d) => setState(() => _digits += d)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.backspace_outlined),
                  onPressed: _digits.isEmpty
                      ? null
                      : () => setState(() => _digits = _digits.substring(0, _digits.length - 1)),
                ),
                FloatingActionButton(
                  backgroundColor: Colors.green,
                  onPressed: _digits.isEmpty ? null : _call,
                  child: const Icon(Icons.call),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
