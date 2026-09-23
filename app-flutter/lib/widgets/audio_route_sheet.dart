import 'package:flutter/material.dart';

import '../services/sip_channel.dart';
import '../utils/audio_route_ui.dart';

/// Route picker shown when Bluetooth or a headset is available.
class AudioRouteSheet extends StatelessWidget {
  const AudioRouteSheet({super.key, required this.routes, required this.onSelect});

  final AudioRoutes routes;
  final ValueChanged<AudioRoute> onSelect;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Audio-Ausgabe', style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final r in routes.routes)
            ListTile(
              leading: Icon(audioRouteIcon(r.type)),
              title: Text(r.name.isNotEmpty ? r.name : audioRouteLabel(r.type)),
              trailing: r.id == routes.currentId ? Icon(Icons.check, color: primary) : null,
              onTap: () => onSelect(r),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
