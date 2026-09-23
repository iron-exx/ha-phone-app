import 'dart:async';

import 'package:flutter/material.dart';

import '../services/call_events.dart';
import '../services/sip_channel.dart';
import '../widgets/dialpad_grid.dart';

/// Replaces the old native ActiveCallActivity, minus audio-routing UI
/// (CallControlScope.availableEndpoints) -- deliberately cut from Phase 1
/// scope (see the migration plan). Reached either from DialpadScreen (right
/// after placing an outgoing call) or from IncomingCallActivity's native
/// "navigateTo: active_call" hand-off after a real Answer tap.
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _muted = false;
  bool _onHold = false;
  StreamSubscription<CallEvent>? _events;

  @override
  void initState() {
    super.initState();
    final alreadyEnded = CallEvents.instance.lastDisconnected;
    if (alreadyEnded != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _leave(message: 'Anruf beendet: ${alreadyEnded.disconnectReason ?? ''}'),
      );
    }
    _events = CallEvents.instance.stream.listen((event) {
      if (event is CallStateEvent && event.state == 'disconnected') {
        _leave(message: 'Anruf beendet: ${event.disconnectReason ?? ''}');
      }
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  void _leave({String? message}) {
    if (!mounted) return;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    await SipChannel.instance.mute(next);
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _toggleHold() async {
    final next = !_onHold;
    await SipChannel.instance.hold(next);
    if (mounted) setState(() => _onHold = next);
  }

  Future<void> _endCall() async {
    try {
      await SipChannel.instance.hangup();
    } catch (e) {
      debugPrint('hangup failed: $e');
    }
    _leave();
  }

  void _showKeypad() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Keypad'),
            const SizedBox(height: 16),
            DialpadGrid(onDigit: SipChannel.instance.sendDtmf),
          ],
        ),
      ),
    );
  }

  void _showTransfer() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => _TransferSheet(
        onTransfer: (target) {
          SipChannel.instance.transfer(target);
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Im Gespräch'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _toggleMute,
                  icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                  label: Text(_muted ? 'Unmute' : 'Mute'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _toggleHold,
                  icon: Icon(_onHold ? Icons.play_arrow : Icons.pause),
                  label: Text(_onHold ? 'Unhold' : 'Hold'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _showKeypad,
                  icon: const Icon(Icons.dialpad),
                  label: const Text('Keypad'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _showTransfer,
                  icon: const Icon(Icons.phone_forwarded),
                  label: const Text('Transfer'),
                ),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: _endCall,
              icon: const Icon(Icons.call_end),
              label: const Text('End Call'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({required this.onTransfer});
  final ValueChanged<String> onTransfer;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  String _target = '';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Transfer an'),
          Text(
            _target.isEmpty ? 'Nebenstelle eingeben' : _target,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          DialpadGrid(onDigit: (d) => setState(() => _target += d)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _target.isEmpty ? null : () => widget.onTransfer(_target),
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
  }
}
