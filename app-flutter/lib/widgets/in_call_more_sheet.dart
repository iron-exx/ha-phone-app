import 'package:flutter/material.dart';

import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'audio_route_sheet.dart';
import 'door_card.dart' show doorActionIcon;
import 'nw_widgets.dart';

/// One tile of the "Mehr" sheet. A null [onTap] shows it disabled with
/// [disabledReason] underneath (also read by TalkBack).
class MoreTile {
  const MoreTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.disabledReason,
    this.iconColor,
    this.key,
    this.semanticLabel,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? disabledReason;
  final Color? iconColor;
  final Key? key;
  final String? semanticLabel;
}

/// "Mehr" in a call: 3-column tiles (Konferenz · Rückfrage · Aufnehmen ·
/// Direkt weiterleiten · Audio-Ausgabe · Anruf-Info), then the audio output
/// list and, for door stations, the further Home Assistant actions. Every
/// action closes the sheet first; the screen runs it.
class InCallMoreSheet extends StatelessWidget {
  const InCallMoreSheet({
    super.key,
    required this.tiles,
    this.routes,
    this.onRoute,
    this.doorActions = const [],
    this.onDoorAction,
  });

  final List<MoreTile> tiles;
  final AudioRoutes? routes;
  final ValueChanged<AudioRoute>? onRoute;

  /// (index, label) of door actions not already on the grid.
  final List<(int, String)> doorActions;
  final void Function(int index, String label)? onDoorAction;

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.textScalerOf(context).scale(10) / 10 >= 1.5 ? 2 : 3;
    final r = routes;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Mehr im Gespräch',
                    style: NwType.display(20).copyWith(color: context.nw.text), textAlign: TextAlign.center),
              ),
            ),
            _grid(context, columns),
            if (r != null && r.routes.isNotEmpty && onRoute != null) ...[
              const SectionHeader('Audio-Ausgabe', padding: EdgeInsets.fromLTRB(0, 20, 0, 8)),
              AudioRouteList(routes: r, onSelect: onRoute!),
            ],
            if (doorActions.isNotEmpty && onDoorAction != null) ...[
              const SectionHeader('Tür-Aktionen', padding: EdgeInsets.fromLTRB(0, 20, 0, 8)),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (index, label) in doorActions)
                    NwChip(
                      key: Key('door-action-$index'),
                      label: label,
                      icon: doorActionIcon(label),
                      onTap: () => onDoorAction!(index, label),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, int columns) {
    final rows = <Widget>[];
    for (var start = 0; start < tiles.length; start += columns) {
      final row = tiles.sublist(start, (start + columns).clamp(0, tiles.length));
      rows.add(Padding(
        padding: EdgeInsets.only(top: start == 0 ? 0 : 10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < columns; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: i < row.length ? _MoreTileView(tile: row[i]) : const SizedBox.shrink()),
              ],
            ],
          ),
        ),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _MoreTileView extends StatelessWidget {
  const _MoreTileView({required this.tile});

  final MoreTile tile;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final enabled = tile.onTap != null;
    final reason = enabled ? null : tile.disabledReason;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    return Semantics(
      key: tile.key,
      button: true,
      enabled: enabled,
      label: tile.semanticLabel ?? tile.label,
      hint: reason,
      onTap: tile.onTap,
      excludeSemantics: true,
      child: Material(
        color: c.raised,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: tile.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 92),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Opacity(
                opacity: enabled ? 1 : 0.45,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tile.icon, size: 24, color: tile.iconColor ?? c.text),
                    const SizedBox(height: 8),
                    Text(
                      tile.label,
                      textAlign: TextAlign.center,
                      style: NwType.meta.copyWith(fontWeight: FontWeight.w700, color: c.text),
                    ),
                    if (reason != null) ...[
                      const SizedBox(height: 2),
                      Text(reason, textAlign: TextAlign.center, style: NwType.meta.copyWith(fontSize: 11, color: c.faint)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
