import 'dart:async';

import 'package:flutter/material.dart';

import '../services/call_events.dart';
import '../services/sip_channel.dart';
import '../theme/app_colors.dart';

/// Green bar above the tabs while a call is up, so a call left via the back
/// gesture or after hanging up one of two lines is never "lost".
class OngoingCallBanner extends StatefulWidget {
  const OngoingCallBanner({super.key});

  @override
  State<OngoingCallBanner> createState() => _OngoingCallBannerState();
}

class _OngoingCallBannerState extends State<OngoingCallBanner> {
  CurrentCall? _call;
  StreamSubscription<CallEvent>? _events;

  @override
  void initState() {
    super.initState();
    _events = CallEvents.instance.stream.listen((e) {
      if (e is CallStateEvent) _refresh();
    });
    _refresh();
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final call = await SipChannel.instance.getCurrentCall();
      if (mounted) setState(() => _call = call);
    } catch (_) {
      // No channel (tests) or no call: no banner.
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    if (call == null) return const SizedBox.shrink();
    final who = call.name.isNotEmpty ? call.name : call.number;
    return Material(
      color: AppColors.answer,
      child: InkWell(
        key: const Key('ongoing-call'),
        onTap: () async {
          await Navigator.of(context).pushNamed('/active-call');
          _refresh();
        },
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.call, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    call.other != null ? 'Gespräch läuft: $who (+1)' : 'Gespräch läuft: $who',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Text('Zurück', style: TextStyle(color: Colors.white)),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
