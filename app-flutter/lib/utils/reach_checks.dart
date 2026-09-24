// Pure logic of the "Erreichbarkeit" screen: which checks pass, the summary
// line and OEM-specific advice. Widgets only render what these return.

import '../models/reachability.dart';
import '../models/ring_settings.dart';

String _two(int n) => n.toString().padLeft(2, '0');

enum ReachCheckId { notifications, fullScreen, battery, exactAlarm, connection, ringing }

/// How a failed check is fixed.
enum ReachFix {
  /// Open [ReachCheck.settingsPage].
  settings,

  /// Register again (the app fixes it itself).
  reconnect,

  /// Switch "Klingeln auf diesem Handy" back on.
  ringOn,
}

class ReachCheck {
  const ReachCheck({
    required this.id,
    required this.label,
    required this.detail,
    required this.ok,
    this.fix,
    this.settingsPage,
  });

  final ReachCheckId id;
  final String label;
  final String detail;
  final bool ok;

  /// null while [ok].
  final ReachFix? fix;
  final ReachabilitySettingsPage? settingsPage;
}

String _clock(DateTime t) => '${t.hour}:${_two(t.minute)}';

/// "angemeldet · 18 ms · seit 9:41" for the connection row.
String connectionDetail(ReachabilitySnapshot s, {int? rttMillis}) {
  if (!s.serviceRunning) return 'Hintergrunddienst läuft nicht';
  if (!s.registered) {
    return s.registrationState == 'failed' ? 'Anmeldung fehlgeschlagen' : 'nicht angemeldet';
  }
  final parts = ['angemeldet'];
  if (rttMillis != null) parts.add('$rttMillis ms');
  final last = s.lastRegisteredAt;
  if (last != null) parts.add('zuletzt ${_clock(last)}');
  return parts.join(' · ');
}

/// The six check rows, in screen order.
List<ReachCheck> buildReachChecks(
  ReachabilitySnapshot s,
  RingSettings ring,
  DateTime now, {
  int? rttMillis,
}) {
  ReachCheck settings(ReachCheckId id, String label, bool ok, String okText, String badText,
          ReachabilitySettingsPage page) =>
      ReachCheck(
        id: id,
        label: label,
        detail: ok ? okText : badText,
        ok: ok,
        fix: ok ? null : ReachFix.settings,
        settingsPage: ok ? null : page,
      );
  final connected = s.registered && s.serviceRunning;
  final rings = ring.ringsAt(now);
  return [
    settings(ReachCheckId.notifications, 'Benachrichtigungen', s.notificationsEnabled, 'erlaubt',
        'aus – Anrufe erscheinen nicht', ReachabilitySettingsPage.notifications),
    settings(ReachCheckId.fullScreen, 'Anrufe im Vollbild', s.canUseFullScreenIntent, 'auch bei Sperre',
        'nicht erlaubt – nur eine kleine Meldung', ReachabilitySettingsPage.fullScreenIntent),
    settings(ReachCheckId.battery, 'Akku-Optimierung', s.ignoringBatteryOptimizations, 'ausgenommen',
        'aktiv – Android kann die App schlafen legen', ReachabilitySettingsPage.batteryOptimization),
    settings(ReachCheckId.exactAlarm, 'Genaue Wecker', s.canScheduleExactAlarms, 'erlaubt',
        'nicht erlaubt – Anmeldung nur ungefähr', ReachabilitySettingsPage.exactAlarm),
    ReachCheck(
      id: ReachCheckId.connection,
      label: 'Verbindung zur Anlage',
      detail: connectionDetail(s, rttMillis: rttMillis),
      ok: connected,
      fix: connected ? null : ReachFix.reconnect,
    ),
    ReachCheck(
      id: ReachCheckId.ringing,
      label: 'Klingeln auf diesem Handy',
      detail: rings ? 'an' : ringDetailText(ring, now),
      ok: rings,
      fix: rings ? null : ReachFix.ringOn,
    ),
  ];
}

class ReachSummary {
  const ReachSummary({required this.passed, required this.total});
  final int passed;
  final int total;

  bool get allOk => passed == total;

  String get title => allOk
      ? 'Alles bereit'
      : total - passed == 1
          ? 'Fast alles bereit'
          : 'Handy ist nicht sicher erreichbar';

  String get text {
    final count = '$passed von $total Punkten erfüllt.';
    return allOk ? '$count Anrufe kommen auch bei gesperrtem Handy.' : '$count Tippe auf „Beheben“.';
  }
}

ReachSummary summarize(List<ReachCheck> checks) =>
    ReachSummary(passed: checks.where((c) => c.ok).length, total: checks.length);

/// Anything that keeps calls from ringing (the amber dot on the Ich tab).
bool hasReachProblems(ReachabilitySnapshot? s, RingSettings ring, DateTime now) {
  if (s == null) return !ring.ringsAt(now);
  return buildReachChecks(s, ring, now).any((c) => !c.ok);
}

class OemAdvice {
  const OemAdvice(this.title, this.steps);
  final String title;
  final List<String> steps;
}

/// Vendor-specific extra steps: these systems stop background apps on their
/// own, even with the battery exemption. null for stock Android.
OemAdvice? oemAdviceFor(OemFamily family) => switch (family) {
      OemFamily.samsung => const OemAdvice('Samsung: App nie schlafen legen', [
          'Einstellungen → Akku → Hintergrundnutzungslimits öffnen.',
          '„Nie in Standby versetzte Apps“ → „+“ → HA-Phone hinzufügen.',
          'HA-Phone aus „Apps im Standby“ und „Apps im Tiefschlaf“ entfernen.',
        ]),
      OemFamily.xiaomi => const OemAdvice('Xiaomi: Autostart und Akku', [
          'Einstellungen → Apps → Apps verwalten → HA-Phone → Autostart einschalten.',
          'Dort „Akkusparmodus“ → „Keine Einschränkungen“ wählen.',
          'In den letzten Apps HA-Phone nach unten ziehen und mit dem Schloss sperren.',
        ]),
      OemFamily.huawei => const OemAdvice('Huawei/Honor: App-Start', [
          'Einstellungen → Akku → App-Start → HA-Phone.',
          '„Automatisch verwalten“ ausschalten.',
          'Autostart, Zweitstart und „Im Hintergrund ausführen“ einschalten.',
        ]),
      OemFamily.oneplus => const OemAdvice('OnePlus: Akku-Optimierung', [
          'Einstellungen → Akku → Akku-Optimierung → HA-Phone → „Nicht optimieren“.',
          'Einstellungen → Apps → HA-Phone → Akku → „Hintergrundaktivität zulassen“.',
          'In den letzten Apps HA-Phone mit dem Schloss sperren.',
        ]),
      OemFamily.oppo => const OemAdvice('Oppo/Realme: Hintergrund erlauben', [
          'Einstellungen → Apps → App-Verwaltung → HA-Phone → Akkunutzung.',
          '„Aktivität im Hintergrund zulassen“ und „Automatischen Start zulassen“ einschalten.',
          'In den letzten Apps HA-Phone mit dem Schloss sperren.',
        ]),
      OemFamily.vivo => const OemAdvice('Vivo: Hintergrund erlauben', [
          'Einstellungen → Akku → Hintergrund-Energieverbrauch → HA-Phone erlauben.',
          'i Manager → App-Verwaltung → Autostart → HA-Phone einschalten.',
        ]),
      OemFamily.google || OemFamily.other => null,
    };
