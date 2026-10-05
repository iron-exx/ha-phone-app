/// Corner radii of the Nachtwache shapes, "runder" step of the
/// 2026-10-05 spec (§3). Theme, cards, buttons, dialpad and call controls
/// read these constants. A few one-off radii (chips, overlays, door action
/// tiles, sheet rows) are intentionally local.
abstract final class NwRadius {
  /// Cards: NwCard default and CardTheme. Was 22.
  static const double card = 26;

  /// Compact cards (status, voicemail, dialer match, banners). Was 18.
  static const double cardSmall = 22;

  /// Medium cards (favourites, groups, checks). Was 20.
  static const double cardMedium = 24;

  /// Large cards: door card, video card, dialogs. Was 26.
  static const double cardLarge = 30;

  /// In-call control tiles (Stumm, Halten, Lautsprecher …). Was 22.
  static const double control = 26;

  /// Dialpad keys at full height (≥ 60 dp). Was 22.
  static const double dialKey = 26;

  /// Compact dialpad keys (in-call keypad, transfer). Was 18.
  static const double dialKeyCompact = 22;

  /// Buttons and keys: FilledButton/OutlinedButton/TextButton theme,
  /// NwPillButton, NwIconButton, door button. Was 16.
  static const double button = 20;

  /// Text fields, snack bars, popup menus (unchanged).
  static const double field = 16;

  /// Ink shape and the call button inside list rows (Verlauf, Kontakte).
  /// Was square ink and 14.
  static const double row = 18;

  /// Top corners of bottom sheets (unchanged).
  static const double sheet = 30;

  /// Center "Wählen" button of the bottom bar. Was 24.
  static const double dialButton = 26;
}
