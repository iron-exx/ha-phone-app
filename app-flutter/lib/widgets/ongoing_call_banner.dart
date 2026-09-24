import 'dart:async';

import 'package:flutter/material.dart';

import '../services/call_events.dart';
import '../services/call_launcher.dart';
import '../services/presence_repository.dart';
import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../utils/call_flip.dart';

/// Bar above the tabs ([child]):
/// - green while this app has a call, so a call left via the back gesture or
///   after hanging up one of two lines is never "lost";
/// - "Gespräch auf anderem Gerät · Hierher holen" while the own extension
///   talks on another device (desk phone), which dials [kCallFlipCode].
/// While a bar is shown it covers the status bar, so the tabs' app bars
/// don't add the top inset a second time.
class OngoingCallBanner extends StatefulWidget {
  const OngoingCallBanner({super.key, required this.child, PresenceRepository? presence}) : _presence = presence;

  final Widget child;
  final PresenceRepository? _presence;

  @override
  State<OngoingCallBanner> createState() => _OngoingCallBannerState();
}

class _OngoingCallBannerState extends State<OngoingCallBanner> {
  CurrentCall? _call;
  DateTime? _callEndedAt;
  StreamSubscription<CallEvent>? _events;

  PresenceRepository get _presence => widget._presence ?? PresenceRepository.instance;

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
      if (!mounted) return;
      setState(() {
        // Our own call kept the line "busy" in the last presence snapshot.
        if (_call != null && call == null) _callEndedAt = DateTime.now();
        _call = call;
      });
    } catch (_) {
      // No channel (tests) or no call: no banner.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _presence,
      builder: (context, _) {
        final call = _call;
        final Widget? bar;
        if (call != null) {
          bar = _ongoingBar(call);
        } else if (_offerFlip()) {
          bar = _flipBar(context);
        } else {
          bar = null;
        }
        return Column(
          children: [
            bar ?? const SizedBox.shrink(),
            Expanded(
              child: MediaQuery.removePadding(context: context, removeTop: bar != null, child: widget.child),
            ),
          ],
        );
      },
    );
  }

  bool _offerFlip() => shouldOfferCallFlip(
        ownLine: _presence.error == null ? _presence.snapshot?.self?.line : null,
        hasOwnCall: _call != null,
        snapshotAt: _presence.updatedAt,
        ownCallEndedAt: _callEndedAt,
      );

  Widget _ongoingBar(CurrentCall call) {
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

  Widget _flipBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('call-flip'),
      color: scheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Icon(Icons.phone_in_talk, color: scheme.onPrimaryContainer, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Gespräch auf anderem Gerät',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('call-flip-take'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.answer,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => CallLauncher.call(context, kCallFlipCode),
                child: const Text('Hierher holen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
