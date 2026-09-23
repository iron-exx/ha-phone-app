import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Material 3 light/dark themes with the HA-Blau accent instead of the
/// default purple. The app follows the system setting (ThemeMode.system).
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final accent = isDark ? AppColors.haBlueLight : AppColors.haBlue;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.haBlue,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      onPrimary: isDark ? AppColors.ink : Colors.white,
      error: AppColors.hangup,
      surface: isDark ? AppColors.ink : AppColors.paper,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: accent.withOpacity(0.18),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withOpacity(0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
