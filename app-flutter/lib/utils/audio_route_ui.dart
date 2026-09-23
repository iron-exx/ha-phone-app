import 'package:flutter/material.dart';

import '../services/sip_channel.dart';

/// German button label for the current audio route.
String audioRouteLabel(String? type) => switch (type) {
      'speaker' => 'Lautsprecher',
      'bluetooth' => 'Bluetooth',
      'headset' => 'Headset',
      'earpiece' => 'Hörer',
      _ => 'Lautsprecher',
    };

IconData audioRouteIcon(String? type) => switch (type) {
      'speaker' => Icons.volume_up,
      'bluetooth' => Icons.bluetooth_audio,
      'headset' => Icons.headset,
      'earpiece' => Icons.phone_in_talk,
      _ => Icons.volume_up,
    };

/// With Bluetooth or a wired headset in play a plain toggle is ambiguous,
/// so the Lautsprecher button opens a route picker instead.
bool needsRoutePicker(AudioRoutes routes) =>
    routes.routes.any((r) => r.type == 'bluetooth' || r.type == 'headset');

/// Route to switch to when toggling between earpiece and speaker, or null if
/// the target isn't available.
AudioRoute? toggleTarget(AudioRoutes routes) {
  final wanted = routes.current?.type == 'speaker' ? 'earpiece' : 'speaker';
  for (final r in routes.routes) {
    if (r.type == wanted) return r;
  }
  return null;
}
