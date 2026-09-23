import 'package:flutter/material.dart';

/// Fixed colour roles of the design system (see docs/linkus-schlachtplan.html,
/// "Design-System"). Green and red are reserved for call actions so their
/// meaning is never diluted; presence colours are only used for status.
abstract final class AppColors {
  /// "HA-Blau" accent (logo colour), light theme.
  static const haBlue = Color(0xFF0284C7);

  /// Lighter accent for the dark theme (enough contrast on dark ground).
  static const haBlueLight = Color(0xFF38BDF8);

  /// Answer / call buttons only.
  static const answer = Color(0xFF2E7D32);

  /// Hang-up buttons and "verpasst" only.
  static const hangup = Color(0xFFD32F2F);

  static const presenceAvailable = Color(0xFF22C55E);
  static const presenceAway = Color(0xFFF59E0B);
  static const presenceLunch = Color(0xFFF97316);
  static const presenceOffline = Color(0xFF9CA3AF);
  static const presenceBusy = Color(0xFFEF4444);

  static const paper = Color(0xFFF8FAFC);
  static const ink = Color(0xFF0F172A);
}

/// Numbers and durations use tabular figures so digits don't jitter while a
/// call timer ticks or rows of numbers are compared.
TextStyle? tabular(TextStyle? style) =>
    style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
