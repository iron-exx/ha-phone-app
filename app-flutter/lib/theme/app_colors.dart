import 'package:flutter/material.dart';

/// Colour roles of the "Nachtwache" design system
/// (docs/design/nachtwache.md). Widgets read the roles of the current
/// brightness via `context.nw`; dark is the reference, light uses the same
/// roles. Green is reserved for answering/calling, red for hang-up, missed
/// and REC, amber for the door.
@immutable
class NwColors extends ThemeExtension<NwColors> {
  const NwColors({
    required this.ground,
    required this.surface,
    required this.raised,
    required this.high,
    required this.stroke,
    required this.text,
    required this.muted,
    required this.faint,
    required this.blue,
    required this.blueInk,
    required this.blueSoft,
    required this.blueOnSoft,
    required this.answer,
    required this.answerInk,
    required this.end,
    required this.endInk,
    required this.endStrong,
    required this.door,
    required this.doorInk,
    required this.doorSoft,
    required this.okSurface,
    required this.okStroke,
    required this.okText,
    required this.offline,
  });

  /// Background of every screen.
  final Color ground;

  /// Cards, text fields, dialpad keys.
  final Color surface;

  /// Chips, control buttons, secondary buttons.
  final Color raised;

  /// Avatar background.
  final Color high;

  /// Lines and card borders.
  final Color stroke;
  final Color text;
  final Color muted;
  final Color faint;

  /// App accent (HA blue) with its ink (text on blue) and soft fill (selected chip/tab).
  final Color blue;
  final Color blueInk;
  final Color blueSoft;

  /// Text on [blueSoft] (selected chips).
  final Color blueOnSoft;

  /// Answer/call buttons only.
  final Color answer;
  final Color answerInk;

  /// Hang-up, missed calls, REC only.
  final Color end;
  final Color endInk;

  /// Darker [end] fill behind text labels ("Löschen", REC chip, badges):
  /// [endInk] on it reaches 4.5:1 (dark [end] is only 3.9:1, fine for icons).
  final Color endStrong;

  /// Door only.
  final Color door;
  final Color doorInk;
  final Color doorSoft;

  /// Green hint surfaces ("Klingelt hier", call flip, all good).
  final Color okSurface;
  final Color okStroke;
  final Color okText;

  /// Offline presence (grey, no ring).
  final Color offline;

  static const dark = NwColors(
    ground: Color(0xFF0B0F14),
    surface: Color(0xFF131A22),
    raised: Color(0xFF1B2430),
    high: Color(0xFF243040),
    stroke: Color(0xFF2A3544),
    text: Color(0xFFEAF0F6),
    muted: Color(0xFFA3B0BF),
    faint: Color(0xFF8593A3),
    blue: Color(0xFF38BDF8),
    blueInk: Color(0xFF04263A),
    blueSoft: Color(0xFF0E3148),
    blueOnSoft: Color(0xFFBAE6FD),
    answer: Color(0xFF2FBF71),
    answerInk: Color(0xFF032313),
    end: Color(0xFFE5484D),
    endInk: Color(0xFFFFFFFF),
    endStrong: Color(0xFFCC3338),
    door: Color(0xFFF5A524),
    doorInk: Color(0xFF2A1800),
    doorSoft: Color(0xFF3A2A0E),
    okSurface: Color(0xFF0F2A1C),
    okStroke: Color(0xFF1E4D33),
    okText: Color(0xFF7EE2A8),
    offline: Color(0xFF6B7787),
  );

  static const light = NwColors(
    ground: Color(0xFFF4F6F9),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFEAEEF3),
    high: Color(0xFFDCE3EB),
    stroke: Color(0xFFD5DCE4),
    text: Color(0xFF0F172A),
    muted: Color(0xFF475569),
    faint: Color(0xFF5B6778),
    blue: Color(0xFF0369A1),
    blueInk: Color(0xFFFFFFFF),
    blueSoft: Color(0xFFE0F2FE),
    blueOnSoft: Color(0xFF075985),
    answer: Color(0xFF177E45),
    answerInk: Color(0xFFFFFFFF),
    end: Color(0xFFD92D32),
    endInk: Color(0xFFFFFFFF),
    endStrong: Color(0xFFD92D32),
    door: Color(0xFFA86500),
    doorInk: Color(0xFFFFFFFF),
    doorSoft: Color(0xFFFFF1D6),
    okSurface: Color(0xFFE7F7EE),
    okStroke: Color(0xFFB7E4C9),
    okText: Color(0xFF166534),
    offline: Color(0xFF94A3B8),
  );

  @override
  NwColors copyWith({
    Color? ground,
    Color? surface,
    Color? raised,
    Color? high,
    Color? stroke,
    Color? text,
    Color? muted,
    Color? faint,
    Color? blue,
    Color? blueInk,
    Color? blueSoft,
    Color? blueOnSoft,
    Color? answer,
    Color? answerInk,
    Color? end,
    Color? endInk,
    Color? endStrong,
    Color? door,
    Color? doorInk,
    Color? doorSoft,
    Color? okSurface,
    Color? okStroke,
    Color? okText,
    Color? offline,
  }) =>
      NwColors(
        ground: ground ?? this.ground,
        surface: surface ?? this.surface,
        raised: raised ?? this.raised,
        high: high ?? this.high,
        stroke: stroke ?? this.stroke,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        faint: faint ?? this.faint,
        blue: blue ?? this.blue,
        blueInk: blueInk ?? this.blueInk,
        blueSoft: blueSoft ?? this.blueSoft,
        blueOnSoft: blueOnSoft ?? this.blueOnSoft,
        answer: answer ?? this.answer,
        answerInk: answerInk ?? this.answerInk,
        end: end ?? this.end,
        endInk: endInk ?? this.endInk,
        endStrong: endStrong ?? this.endStrong,
        door: door ?? this.door,
        doorInk: doorInk ?? this.doorInk,
        doorSoft: doorSoft ?? this.doorSoft,
        okSurface: okSurface ?? this.okSurface,
        okStroke: okStroke ?? this.okStroke,
        okText: okText ?? this.okText,
        offline: offline ?? this.offline,
      );

  @override
  NwColors lerp(NwColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return NwColors(
      ground: l(ground, other.ground),
      surface: l(surface, other.surface),
      raised: l(raised, other.raised),
      high: l(high, other.high),
      stroke: l(stroke, other.stroke),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      blue: l(blue, other.blue),
      blueInk: l(blueInk, other.blueInk),
      blueSoft: l(blueSoft, other.blueSoft),
      blueOnSoft: l(blueOnSoft, other.blueOnSoft),
      answer: l(answer, other.answer),
      answerInk: l(answerInk, other.answerInk),
      end: l(end, other.end),
      endInk: l(endInk, other.endInk),
      endStrong: l(endStrong, other.endStrong),
      door: l(door, other.door),
      doorInk: l(doorInk, other.doorInk),
      doorSoft: l(doorSoft, other.doorSoft),
      okSurface: l(okSurface, other.okSurface),
      okStroke: l(okStroke, other.okStroke),
      okText: l(okText, other.okText),
      offline: l(offline, other.offline),
    );
  }
}

extension NwColorsContext on BuildContext {
  /// Nachtwache colour roles of the current theme (dark tokens if a test
  /// pumps a bare MaterialApp without AppTheme).
  NwColors get nw => Theme.of(this).extension<NwColors>() ?? NwColors.dark;
}

/// Brightness-independent colours for code outside the widget tree's theme
/// (models, native-mirroring UI). Values are the dark Nachtwache tokens;
/// widgets should prefer `context.nw`.
abstract final class AppColors {
  /// "HA-Blau" accent, light theme.
  static const haBlue = Color(0xFF0369A1);

  /// Accent for the dark theme.
  static const haBlueLight = Color(0xFF38BDF8);

  /// Answer / call buttons only.
  static const answer = Color(0xFF2FBF71);

  /// Hang-up buttons and "verpasst" only.
  static const hangup = Color(0xFFE5484D);

  /// "Aufnahme" indicator while a call is recorded.
  static const recording = Color(0xFFE5484D);

  /// Door actions only.
  static const door = Color(0xFFF5A524);

  static const presenceAvailable = Color(0xFF2FBF71);
  static const presenceAway = Color(0xFFF5A524);
  static const presenceLunch = Color(0xFFF5A524);
  static const presenceOffline = Color(0xFF6B7787);
  static const presenceBusy = Color(0xFFE5484D);

  static const paper = Color(0xFFF4F6F9);
  static const ink = Color(0xFF0B0F14);
}

/// Numbers and durations use tabular figures so digits don't jitter while a
/// call timer ticks or rows of numbers are compared.
TextStyle? tabular(TextStyle? style) =>
    style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
