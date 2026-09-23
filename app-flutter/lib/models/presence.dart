import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Presence states as delivered by /api/mobile/directory (`presence_status`
/// in the PBX). [unknown] covers null/unrecognised values and phonebook
/// entries, which carry no presence at all.
enum Presence {
  available('available', 'verfügbar', AppColors.presenceAvailable),
  away('away', 'abwesend', AppColors.presenceAway),
  lunch('lunch', 'Mittagspause', AppColors.presenceLunch),
  offWork('off_work', 'Feierabend', AppColors.presenceOffline),
  doNotDisturb('do_not_disturb', 'nicht stören', AppColors.presenceBusy),
  unknown('', 'unbekannt', AppColors.presenceOffline);

  const Presence(this.apiValue, this.label, this.color);

  final String apiValue;

  /// German label, e.g. for the "13 · verfügbar" subtitle.
  final String label;
  final Color color;

  static Presence fromApi(String? value) {
    for (final p in Presence.values) {
      if (p != unknown && p.apiValue == value) return p;
    }
    return unknown;
  }
}
