import 'package:flutter/material.dart';

import '../models/extension_status.dart';
import '../models/presence.dart';
import '../services/api_client.dart';
import '../services/presence_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'presence_avatar.dart';

/// The five presence states the user can pick, in Linkus order.
const kSelectablePresences = [
  Presence.available,
  Presence.away,
  Presence.lunch,
  Presence.doNotDisturb,
  Presence.offWork,
];

/// Opens the status sheet and stores the pick on the PBX; a failed PUT
/// shows a SnackBar (the repository reverts optimistically).
Future<void> pickOwnPresence(BuildContext context, PresenceRepository presence, Presence current) async {
  final messenger = ScaffoldMessenger.of(context);
  final picked = await PresenceSheet.show(context, current);
  if (picked == null || picked == current) return;
  try {
    await presence.setOwn(picked);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Status nicht gespeichert: ${e.message}')));
  }
}

/// Bottom sheet "Status wählen": one large row per status with its
/// colour-and-glyph badge, check mark on the current one. Returns the
/// picked status, or null when dismissed. (Full "Status & Klingeln" sheet:
/// stage 4 of the redesign.)
class PresenceSheet extends StatelessWidget {
  const PresenceSheet({super.key, required this.current});

  final Presence current;

  static Future<Presence?> show(BuildContext context, Presence current) => showModalBottomSheet<Presence>(
        context: context,
        showDragHandle: true,
        // Sized to its content (the default caps at 9/16 of the screen).
        isScrollControlled: true,
        builder: (_) => PresenceSheet(current: current),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text('Status wählen', style: NwType.display(22).copyWith(color: c.text)),
            ),
            for (final p in kSelectablePresences) ...[
              _row(context, p),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Presence p) {
    final c = context.nw;
    final selected = p == current;
    final kind = avatarPresenceFor(ExtensionStatus(presence: p, line: LineState.idle)) ?? AvatarPresence.available;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: selected ? c.blue : Colors.transparent),
    );
    return Material(
      color: selected ? c.blueSoft : c.raised,
      shape: shape,
      child: ListTile(
        key: ValueKey('presence-${p.apiValue}'),
        shape: shape,
        minTileHeight: 62,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(shape: BoxShape.circle, color: kind.color(c)),
          child: Icon(kind.glyph ?? Icons.circle_outlined, size: 18, color: c.ground),
        ),
        title: Text(p.label, style: NwType.rowTitle.copyWith(color: c.text, fontWeight: FontWeight.w800)),
        subtitle: Text(_hint(p), style: NwType.meta.copyWith(color: c.faint, fontSize: 12)),
        trailing: selected ? Icon(Icons.check, color: c.blue) : null,
        selected: selected,
        onTap: () => Navigator.of(context).pop(p),
      ),
    );
  }

  static String _hint(Presence p) => switch (p) {
        Presence.available => 'Anrufe klingeln wie eingestellt',
        Presence.away => 'Weiterleitung nach Regel „abwesend“',
        Presence.lunch => 'Weiterleitung nach Regel „Mittagspause“',
        Presence.doNotDisturb => 'Keine Anrufe, Regel „nicht stören“',
        Presence.offWork => 'Weiterleitung nach Regel „Feierabend“',
        Presence.unknown => '',
      };
}
