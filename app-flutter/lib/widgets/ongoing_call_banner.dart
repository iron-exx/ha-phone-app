import 'package:flutter/material.dart';

import '../services/own_call_watcher.dart';
import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Green bar above the tabs ([child]) while this app has a call, so a call
/// left via the back gesture or after hanging up one of two lines is never
/// "lost". While shown it covers the status bar, so the tabs don't add the
/// top inset a second time. (The call-flip offer lives on Start:
/// CallFlipCard.)
class OngoingCallBanner extends StatefulWidget {
  const OngoingCallBanner({super.key, required this.child});

  final Widget child;

  @override
  State<OngoingCallBanner> createState() => _OngoingCallBannerState();
}

class _OngoingCallBannerState extends State<OngoingCallBanner> {
  final _watcher = OwnCallWatcher();

  @override
  void dispose() {
    _watcher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _watcher,
      builder: (context, _) {
        final call = _watcher.call;
        return Column(
          children: [
            if (call != null) _bar(context, call),
            Expanded(
              child: MediaQuery.removePadding(context: context, removeTop: call != null, child: widget.child),
            ),
          ],
        );
      },
    );
  }

  Widget _bar(BuildContext context, CurrentCall call) {
    final c = context.nw;
    final who = call.name.isNotEmpty ? call.name : call.number;
    final text = call.other != null ? 'Gespräch läuft: $who (+1)' : 'Gespräch läuft: $who';
    return Material(
      color: c.answer,
      child: InkWell(
        key: const Key('ongoing-call'),
        onTap: () async {
          await Navigator.of(context).pushNamed('/active-call');
          await _watcher.refresh();
        },
        child: SafeArea(
          bottom: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.call, color: c.answerInk, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: NwType.rowTitle.copyWith(color: c.answerInk, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('Zurück', style: NwType.chip.copyWith(color: c.answerInk, fontWeight: FontWeight.w800)),
                  Icon(Icons.chevron_right, color: c.answerInk),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
