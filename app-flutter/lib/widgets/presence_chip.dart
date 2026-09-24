import 'package:flutter/material.dart';

import '../models/extension_status.dart';
import '../models/presence.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'nw_widgets.dart';
import 'presence_avatar.dart';

/// Status pill with the presence glyph (colour + shape). With [onTap] it
/// shows a dropdown arrow and opens the status picker (48 dp target).
class PresenceChip extends StatelessWidget {
  const PresenceChip({super.key, required this.presence, this.onTap});
  final Presence presence;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    // Unknown presence stays neutral (no green check for "unbekannt").
    final kind = presence == Presence.unknown
        ? null
        : avatarPresenceFor(ExtensionStatus(presence: presence, line: LineState.idle));
    final color = kind?.color(c) ?? c.faint;
    final pill = Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: EdgeInsets.fromLTRB(8, 4, onTap == null ? 12 : 6, 4),
      decoration: ShapeDecoration(color: color.withOpacity(0.16), shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Icon(kind?.glyph ?? Icons.circle_outlined, size: 11, color: c.ground),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(presence.label, style: NwType.chip.copyWith(color: c.text, fontWeight: FontWeight.w700))),
          if (onTap != null) Icon(Icons.arrow_drop_down, size: 20, color: c.muted),
        ],
      ),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      hint: 'Status ändern',
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTap),
          child: Align(alignment: Alignment.centerLeft, widthFactor: 1, child: pill),
        ),
      ),
    );
  }
}
