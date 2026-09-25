import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Bundled font families (assets/fonts, OFL).
abstract final class NwFonts {
  /// Titles, big names, numbers (700/800).
  static const display = 'Bricolage';

  /// Everything else (500–800).
  static const ui = 'Manrope';
}

const _tnum = [FontFeature.tabularFigures()];

/// Type scale of the Nachtwache spec. Colours come from the theme, so these
/// are colour-less; callers add `color:` where the role is not `text`.
abstract final class NwType {
  /// Page title: Bricolage 32/800.
  static const pageTitle = TextStyle(
    fontFamily: NwFonts.display,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -0.3,
  );

  /// Big number / name in Bricolage (dialer 40/700, names 26–40/800).
  static TextStyle display(double size, {FontWeight weight = FontWeight.w800}) => TextStyle(
        fontFamily: NwFonts.display,
        fontSize: size,
        fontWeight: weight,
        height: 1.1,
        letterSpacing: -0.01 * size,
        fontFeatures: _tnum,
      );

  /// Row title: Manrope 15/700 (800 for unread/emphasis).
  static const rowTitle = TextStyle(fontFamily: NwFonts.ui, fontSize: 15, fontWeight: FontWeight.w700, height: 1.25);

  /// Meta line: Manrope 12.5/600, tabular.
  static const meta = TextStyle(
    fontFamily: NwFonts.ui,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
    fontFeatures: _tnum,
  );

  /// Section header: 12/800, upper case, +8 % tracking.
  static const section = TextStyle(
    fontFamily: NwFonts.ui,
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 12 * 0.08,
    height: 1.3,
  );

  /// Chip label: 13/600.
  static const chip = TextStyle(fontFamily: NwFonts.ui, fontSize: 13, fontWeight: FontWeight.w600, height: 1.2);

  /// Button label: 15/800.
  static const button = TextStyle(fontFamily: NwFonts.ui, fontSize: 15, fontWeight: FontWeight.w800, height: 1.2);
}

/// Material 3 themes built from the Nachtwache roles. Which one shows is the
/// in-app "Erscheinungsbild" (services/appearance.dart, default Dunkel);
/// switches live.
abstract final class AppTheme {
  static ThemeData light() => build(NwColors.light, Brightness.light);
  static ThemeData dark() => build(NwColors.dark, Brightness.dark);

  /// Android status and navigation bar for a theme brightness: transparent
  /// bars over `ground`, dark icons on the light theme, light icons on the
  /// dark one (without this the light theme had white, unreadable icons).
  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final icons = brightness == Brightness.light ? Brightness.dark : Brightness.light;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      // iOS: brightness of the bar background.
      statusBarBrightness: brightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static ThemeData build(NwColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.blue,
      onPrimary: c.blueInk,
      primaryContainer: c.blueSoft,
      onPrimaryContainer: c.blueOnSoft,
      secondary: c.blue,
      onSecondary: c.blueInk,
      secondaryContainer: c.blueSoft,
      onSecondaryContainer: c.blueOnSoft,
      tertiary: c.door,
      onTertiary: c.doorInk,
      tertiaryContainer: c.doorSoft,
      onTertiaryContainer: c.door,
      error: c.end,
      onError: c.endInk,
      errorContainer: c.end.withOpacity(0.16),
      onErrorContainer: c.end,
      surface: c.ground,
      onSurface: c.text,
      onSurfaceVariant: c.muted,
      surfaceContainerLowest: c.ground,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.raised,
      surfaceContainerHighest: c.raised,
      outline: c.stroke,
      outlineVariant: c.stroke,
      inverseSurface: c.text,
      onInverseSurface: c.ground,
      inversePrimary: c.blueSoft,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );
    final text = _textTheme(c);
    final radius16 = BorderRadius.circular(16);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: NwFonts.ui,
      textTheme: text,
      extensions: [c],
      scaffoldBackgroundColor: c.ground,
      canvasColor: c.ground,
      dividerColor: c.stroke,
      iconTheme: IconThemeData(color: c.text),
      appBarTheme: AppBarTheme(
        backgroundColor: c.ground,
        foregroundColor: c.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: NwType.display(24).copyWith(color: c.text),
        systemOverlayStyle: overlayStyle(brightness),
      ),
      cardTheme: CardTheme(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: c.stroke),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.raised,
        selectedColor: c.blueSoft,
        disabledColor: c.raised,
        labelStyle: NwType.chip.copyWith(color: c.text),
        secondaryLabelStyle: NwType.chip.copyWith(color: c.blueOnSoft),
        side: BorderSide(color: c.stroke),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        showCheckmark: false,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        minVerticalPadding: 10,
        iconColor: c.muted,
        textColor: c.text,
        titleTextStyle: NwType.rowTitle.copyWith(color: c.text),
        subtitleTextStyle: NwType.meta.copyWith(color: c.muted),
        leadingAndTrailingTextStyle: NwType.meta.copyWith(color: c.faint),
        selectedColor: c.blue,
      ),
      dividerTheme: DividerThemeData(color: c.stroke, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hintStyle: text.bodyLarge?.copyWith(color: c.faint),
        labelStyle: text.bodyLarge?.copyWith(color: c.muted),
        prefixIconColor: c.faint,
        suffixIconColor: c.faint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide(color: c.stroke)),
        enabledBorder: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide(color: c.stroke)),
        focusedBorder: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide(color: c.blue, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide(color: c.end)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: radius16, borderSide: BorderSide(color: c.end, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.blue,
          foregroundColor: c.blueInk,
          disabledBackgroundColor: c.raised,
          disabledForegroundColor: c.faint,
          minimumSize: const Size(48, 48),
          textStyle: NwType.button,
          shape: RoundedRectangleBorder(borderRadius: radius16),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: c.stroke),
          textStyle: NwType.button,
          shape: RoundedRectangleBorder(borderRadius: radius16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.blue,
          minimumSize: const Size(48, 48),
          textStyle: NwType.button.copyWith(fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: radius16),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: c.text, minimumSize: const Size(48, 48)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: c.raised,
          foregroundColor: c.text,
          selectedBackgroundColor: c.blueSoft,
          selectedForegroundColor: c.blueOnSoft,
          side: BorderSide(color: c.stroke),
          textStyle: NwType.chip,
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        titleTextStyle: NwType.display(22).copyWith(color: c.text),
        contentTextStyle: text.bodyMedium?.copyWith(color: c.muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
        dragHandleColor: c.stroke,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.text,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.ground, fontWeight: FontWeight.w600),
        actionTextColor: c.blueSoft,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius16),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : c.muted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.answer : c.raised),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.transparent : c.stroke,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.blue : Colors.transparent),
        checkColor: WidgetStatePropertyAll(c.blueInk),
        side: BorderSide(color: c.muted, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.blue : c.muted),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.blue,
        inactiveTrackColor: c.stroke,
        thumbColor: c.blue,
        overlayColor: c.blue.withOpacity(0.12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.blue, linearTrackColor: c.raised),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius16, side: BorderSide(color: c.stroke)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.text, borderRadius: BorderRadius.circular(10)),
        textStyle: text.bodySmall?.copyWith(color: c.ground, fontWeight: FontWeight.w700),
      ),
      badgeTheme: BadgeThemeData(backgroundColor: c.endStrong, textColor: c.endInk),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.blue,
        foregroundColor: c.blueInk,
        elevation: 0,
      ),
    );
  }

  static TextTheme _textTheme(NwColors c) {
    TextStyle d(double size, FontWeight w) =>
        TextStyle(fontFamily: NwFonts.display, fontSize: size, fontWeight: w, color: c.text, height: 1.15);
    TextStyle u(double size, FontWeight w, [Color? color]) =>
        TextStyle(fontFamily: NwFonts.ui, fontSize: size, fontWeight: w, color: color ?? c.text, height: 1.35);
    return TextTheme(
      displayLarge: d(57, FontWeight.w800),
      displayMedium: d(45, FontWeight.w800),
      displaySmall: d(36, FontWeight.w700),
      headlineLarge: d(32, FontWeight.w800),
      headlineMedium: d(28, FontWeight.w800),
      headlineSmall: d(24, FontWeight.w800),
      titleLarge: d(22, FontWeight.w800),
      titleMedium: u(16, FontWeight.w700),
      titleSmall: u(14, FontWeight.w700),
      bodyLarge: u(15, FontWeight.w500),
      bodyMedium: u(14, FontWeight.w500, c.muted),
      bodySmall: u(12.5, FontWeight.w600, c.faint),
      labelLarge: u(14, FontWeight.w700),
      labelMedium: u(12.5, FontWeight.w700),
      labelSmall: u(11, FontWeight.w700),
    );
  }
}

/// Applies [AppTheme.overlayStyle] of the current theme to every screen,
/// also those without an AppBar (Start, call screen, sheets). Used in
/// MaterialApp.builder so it follows live light/dark switches.
class NwSystemUi extends StatelessWidget {
  const NwSystemUi({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.overlayStyle(Theme.of(context).brightness),
        child: child,
      );
}
