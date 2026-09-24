import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'nw_widgets.dart';

/// Look of an in-call control tile.
enum CallControlTone {
  /// `raised` tile, `text` icon.
  normal,

  /// Inverted (`text` fill, `ground` icon): Stumm/Halten/Lautsprecher on.
  active,

  /// Amber door tile ("Tür öffnen").
  door,

  /// Green ok state ("Tür geöffnet ✓").
  done,
}

/// Nachtwache in-call control: 72 dp tonal tile (radius 22) with the label
/// underneath; the tile and label together are one touch target and one
/// TalkBack node. A null [onPressed] renders it disabled.
class CallControlButton extends StatelessWidget {
  const CallControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tone = CallControlTone.normal,
    this.toggled,
    this.semanticLabel,
    this.busy = false,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final CallControlTone tone;

  /// On/off state for TalkBack (Stumm, Halten, Lautsprecher); null = plain button.
  final bool? toggled;

  /// TalkBack label if it should differ from [label].
  final String? semanticLabel;

  /// Shows a spinner instead of the icon (request on its way).
  final bool busy;

  /// Icon colour override for the normal tone (red "Aufnehmen").
  final Color? iconColor;

  bool get active => tone == CallControlTone.active;

  static const tileHeight = 72.0;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final enabled = onPressed != null;
    final (Color bg, Color fg) = switch (tone) {
      CallControlTone.normal => (c.raised, iconColor ?? c.text),
      CallControlTone.active => (c.text, c.ground),
      CallControlTone.door => (c.door, c.doorInk),
      CallControlTone.done => (c.okSurface, c.okText),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: toggled,
      label: semanticLabel ?? label,
      // excludeSemantics drops the InkWell's action, so TalkBack needs it here.
      onTap: onPressed,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: kMinTap, minHeight: kMinTap),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: tileHeight,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(22),
                    border: tone == CallControlTone.done ? Border.all(color: c.okStroke) : null,
                  ),
                  child: busy
                      ? Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
                          ),
                        )
                      : Icon(icon, color: fg, size: 26),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: NwType.meta.copyWith(
                    fontWeight: FontWeight.w700,
                    color: tone == CallControlTone.done ? c.okText : c.muted,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Columns of the control grid: 3 (2×3 per the design), 2 when large system
/// text would squeeze the labels (the screen scrolls then).
int callGridColumns(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) / 10 >= 1.5 ? 2 : 3;

/// Grid of [CallControlButton]s in rows of [columns]; a shorter last row is
/// centred on the same column width. Built from Rows (no LayoutBuilder) so
/// it works inside IntrinsicHeight.
class CallControlGrid extends StatelessWidget {
  const CallControlGrid({super.key, required this.children, required this.columns, this.gap = 14});

  final List<Widget> children;
  final int columns;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += columns) {
      final row = children.sublist(start, (start + columns).clamp(0, children.length));
      final missing = columns - row.length;
      rows.add(Padding(
        padding: EdgeInsets.only(top: start == 0 ? 0 : gap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (missing > 0) Spacer(flex: missing),
            for (final (i, b) in row.indexed) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(flex: 2, child: b),
            ],
            if (missing > 0) Spacer(flex: missing),
          ],
        ),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// Red "● REC 00:18" chip while the line on screen is recorded.
class RecChip extends StatelessWidget {
  const RecChip({super.key, required this.elapsed});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final time = formatCallTimer(elapsed);
    return Semantics(
      label: 'Aufnahme läuft, $time',
      excludeSemantics: true,
      child: Container(
        key: const Key('recording-indicator'),
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.endStrong, borderRadius: BorderRadius.circular(14)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: c.endInk, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(
              'REC $time',
              style: NwType.chip.copyWith(color: c.endInk, fontWeight: FontWeight.w800, fontSize: 12)
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
      ),
    );
  }
}
