import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/forwarding.dart';
import 'package:ha_phone_test/models/presence.dart';
import 'package:ha_phone_test/models/reachability.dart';
import 'package:ha_phone_test/models/ring_settings.dart';
import 'package:ha_phone_test/utils/presence_hint.dart';
import 'package:ha_phone_test/utils/reach_checks.dart';

ReachabilitySnapshot _snap({
  bool notifications = true,
  bool fullScreen = true,
  bool battery = true,
  bool exact = true,
  bool registered = true,
  bool service = true,
  OemFamily oem = OemFamily.google,
}) =>
    ReachabilitySnapshot(
      notificationsEnabled: notifications,
      canUseFullScreenIntent: fullScreen,
      ignoringBatteryOptimizations: battery,
      canScheduleExactAlarms: exact,
      registered: registered,
      serviceRunning: service,
      registrationState: registered ? 'registered' : 'failed',
      lastRegisteredAt: DateTime(2026, 9, 24, 9, 41),
      oemFamily: oem,
    );

void main() {
  final now = DateTime(2026, 9, 24, 10);

  group('buildReachChecks', () {
    test('all six pass on a healthy phone', () {
      final checks = buildReachChecks(_snap(), const RingSettings(), now, rttMillis: 18);
      expect(checks.map((c) => c.label), [
        'Benachrichtigungen',
        'Anrufe im Vollbild',
        'Akku-Optimierung',
        'Genaue Wecker',
        'Verbindung zur Anlage',
        'Klingeln auf diesem Handy',
      ]);
      expect(checks.every((c) => c.ok), isTrue);
      expect(checks[4].detail, 'angemeldet · 18 ms · zuletzt 9:41');
      final s = summarize(checks);
      expect(s.allOk, isTrue);
      expect(s.text, startsWith('6 von 6 Punkten erfüllt.'));
      expect(s.title, 'Alles bereit');
    });

    test('failed checks point at the right fix', () {
      final checks = buildReachChecks(
        _snap(notifications: false, fullScreen: false, battery: false, exact: false, registered: false),
        const RingSettings(enabled: false),
        now,
      );
      expect(checks.where((c) => c.ok), isEmpty);
      expect(checks.map((c) => c.settingsPage).take(4), [
        ReachabilitySettingsPage.notifications,
        ReachabilitySettingsPage.fullScreenIntent,
        ReachabilitySettingsPage.batteryOptimization,
        ReachabilitySettingsPage.exactAlarm,
      ]);
      expect(checks[4].fix, ReachFix.reconnect);
      expect(checks[4].detail, 'Anmeldung fehlgeschlagen');
      expect(checks[5].fix, ReachFix.ringOn);
      expect(summarize(checks).text, startsWith('0 von 6 Punkten erfüllt.'));
    });

    test('one problem = "Fast alles bereit"; a timed mute is a warning', () {
      final checks = buildReachChecks(_snap(), RingSettings(mutedUntil: DateTime(2026, 9, 24, 17)), now);
      final s = summarize(checks);
      expect(s.passed, 5);
      expect(s.title, 'Fast alles bereit');
      expect(checks.last.detail, startsWith('stumm bis 17:00'));
    });

    test('stopped service beats the registration flag', () {
      expect(connectionDetail(_snap(service: false)), 'Hintergrunddienst läuft nicht');
      expect(buildReachChecks(_snap(service: false), const RingSettings(), now)[4].ok, isFalse);
    });

    test('hasReachProblems without a snapshot only looks at ringing', () {
      expect(hasReachProblems(null, const RingSettings(), now), isFalse);
      expect(hasReachProblems(null, const RingSettings(enabled: false), now), isTrue);
      expect(hasReachProblems(_snap(exact: false), const RingSettings(), now), isTrue);
      expect(hasReachProblems(_snap(), const RingSettings(), now), isFalse);
    });
  });

  group('oemAdviceFor', () {
    test('Samsung, Xiaomi, Huawei, OnePlus, Oppo get concrete steps', () {
      for (final f in [OemFamily.samsung, OemFamily.xiaomi, OemFamily.huawei, OemFamily.oneplus, OemFamily.oppo]) {
        final a = oemAdviceFor(f);
        expect(a, isNotNull, reason: f.name);
        expect(a!.steps, isNotEmpty);
      }
      expect(oemAdviceFor(OemFamily.samsung)!.steps.join(), contains('Nie in Standby versetzte Apps'));
      expect(oemAdviceFor(OemFamily.xiaomi)!.steps.join(), contains('Autostart'));
    });

    test('stock Android gets none', () {
      expect(oemAdviceFor(OemFamily.google), isNull);
      expect(oemAdviceFor(OemFamily.other), isNull);
    });
  });

  group('presenceHint', () {
    String name(String n) => n == '11' ? 'sandro' : '';

    test('generic text while the rules are unknown', () {
      expect(presenceHint(Presence.available, null, name), 'Anrufe klingeln wie eingestellt');
      expect(presenceHint(Presence.doNotDisturb, null, name), contains('nicht stören'));
    });

    test('same rule for both directions', () {
      final rules = [
        for (final d in ForwardDirection.values)
          ForwardingRule(status: 'away', direction: d, mode: ForwardMode.ringThenDest, destType: ForwardDestType.voicemail),
      ];
      expect(presenceHint(Presence.away, rules, name), 'Nach 20 s zur Mailbox');
      expect(presenceHint(Presence.available, rules, name), 'Normal klingeln');
    });

    test('different rules per direction', () {
      final rules = [
        const ForwardingRule(
            status: 'off_work', direction: ForwardDirection.external, mode: ForwardMode.alwaysDest,
            destType: ForwardDestType.extension, destTarget: '11'),
      ];
      expect(presenceHint(Presence.offWork, rules, name), 'Intern: Normal klingeln · Extern: Sofort zu 11 · sandro');
    });

    test('Mittagspause only listed while it is the current status', () {
      expect(statusChoices(Presence.available), [Presence.available, Presence.away, Presence.doNotDisturb, Presence.offWork]);
      expect(statusChoices(Presence.lunch), contains(Presence.lunch));
    });
  });
}
