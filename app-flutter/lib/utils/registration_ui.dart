import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// UI state of the SIP registration for the Ich tab.
enum RegistrationUi {
  online('Online (TLS)', AppColors.presenceAvailable),
  offline('Nicht verbunden', AppColors.hangup),
  connecting('Verbinde…', AppColors.presenceAway);

  const RegistrationUi(this.label, this.color);
  final String label;
  final Color color;

  /// Maps SipChannel.getRegistrationState / RegistrationStateEvent values.
  /// The app only registers over TLS (see HANDOFF), hence "Online (TLS)".
  static RegistrationUi fromState(String state) => switch (state) {
        'registered' => online,
        'failed' || 'unregistered' => offline,
        _ => connecting,
      };
}
