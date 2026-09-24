import 'package:flutter/material.dart';

import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/audio_route_ui.dart';
import 'nw_widgets.dart';

/// Name shown for a route: Bluetooth/headset devices by their own name
/// ("Pixel Buds"), earpiece and speaker in German.
String audioRouteName(AudioRoute r) =>
    (r.type == 'bluetooth' || r.type == 'headset') && r.name.isNotEmpty ? r.name : audioRouteLabel(r.type);

/// Route picker shown when Bluetooth or a headset is available.
class AudioRouteSheet extends StatelessWidget {
  const AudioRouteSheet({super.key, required this.routes, required this.onSelect});

  final AudioRoutes routes;
  final ValueChanged<AudioRoute> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('Audio-Ausgabe', padding: EdgeInsets.fromLTRB(0, 0, 0, 10)),
            AudioRouteList(routes: routes, onSelect: onSelect),
          ],
        ),
      ),
    );
  }
}

/// Audio outputs as 54 dp rows; the current one is blue-soft with a check.
class AudioRouteList extends StatelessWidget {
  const AudioRouteList({super.key, required this.routes, required this.onSelect});

  final AudioRoutes routes;
  final ValueChanged<AudioRoute> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, r) in routes.routes.indexed) ...[
          if (i > 0) const SizedBox(height: 6),
          _row(c, r, selected: r.id == routes.currentId),
        ],
      ],
    );
  }

  Widget _row(NwColors c, AudioRoute r, {required bool selected}) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: selected ? BorderSide(color: c.blue) : BorderSide.none,
    );
    final name = audioRouteName(r);
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      onTap: () => onSelect(r),
      excludeSemantics: true,
      child: Material(
        key: ValueKey('audio-route-${r.id}'),
        color: selected ? c.blueSoft : c.raised,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: () => onSelect(r),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Icon(audioRouteIcon(r.type), size: 20, color: selected ? c.blue : c.text),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: NwType.rowTitle.copyWith(color: selected ? c.blueOnSoft : c.text),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected) Icon(Icons.check_rounded, size: 18, color: c.blue),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
