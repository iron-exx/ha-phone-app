import 'package:flutter/material.dart';

import 'nw_shapes.dart';

/// Background layers for `FilledButton` (`ButtonStyle.backgroundBuilder`).
abstract final class NwButtons {
  /// Theme default: brand gradient behind enabled buttons. `Ink` paints on
  /// the button's Material, so the press ripple stays visible. Disabled
  /// buttons keep the flat `disabledBackgroundColor`.
  static ButtonLayerBuilder brand(LinearGradient gradient) => (context, states, child) {
        final content = child ?? const SizedBox.shrink();
        if (states.contains(WidgetState.disabled)) return content;
        return Ink(
          decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(NwRadius.button)),
          child: content,
        );
      };

  /// Opt-out for FilledButtons with their own status colour (answer, end,
  /// door, ok). Without it the theme gradient would paint over their
  /// `backgroundColor`. test/filled_button_opt_out_test.dart enforces it.
  static Widget solid(BuildContext context, Set<WidgetState> states, Widget? child) =>
      child ?? const SizedBox.shrink();
}
