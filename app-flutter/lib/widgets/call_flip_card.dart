import 'package:flutter/material.dart';

import '../services/call_launcher.dart';
import '../services/own_call_watcher.dart';
import '../services/presence_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/call_flip.dart';

/// Start card "Gespräch auf anderem Gerät → Hierher holen" while the own
/// extension talks on another device (desk phone) and this app has no call
/// of its own; dials [kCallFlipCode]. Renders nothing otherwise.
class CallFlipCard extends StatefulWidget {
  const CallFlipCard({super.key, PresenceRepository? presence}) : _presence = presence;

  final PresenceRepository? _presence;

  @override
  State<CallFlipCard> createState() => _CallFlipCardState();
}

class _CallFlipCardState extends State<CallFlipCard> {
  final _watcher = OwnCallWatcher();

  PresenceRepository get _presence => widget._presence ?? PresenceRepository.instance;

  @override
  void dispose() {
    _watcher.dispose();
    super.dispose();
  }

  bool _offer() => shouldOfferCallFlip(
        ownLine: _presence.error == null ? _presence.snapshot?.self?.line : null,
        hasOwnCall: _watcher.call != null,
        snapshotAt: _presence.updatedAt,
        ownCallEndedAt: _watcher.endedAt,
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_presence, _watcher]),
      builder: (context, _) => _offer() ? _card(context) : const SizedBox.shrink(),
    );
  }

  Widget _card(BuildContext context) {
    final c = context.nw;
    return Padding(
      key: const Key('call-flip'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: c.okSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.okStroke),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          spacing: 12,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.desk_outlined, color: c.okText, size: 22),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Gespräch auf anderem Gerät', style: NwType.rowTitle.copyWith(color: c.text, fontSize: 13.5)),
                      Text('Ihre Nebenstelle telefoniert', style: NwType.meta.copyWith(color: c.okText, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            FilledButton(
              key: const Key('call-flip-take'),
              style: FilledButton.styleFrom(
                backgroundColor: c.answer,
                foregroundColor: c.answerInk,
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: NwType.button.copyWith(fontSize: 13),
              ),
              onPressed: () => CallLauncher.call(context, kCallFlipCode),
              child: const Text('Hierher holen'),
            ),
          ],
        ),
      ),
    );
  }
}
