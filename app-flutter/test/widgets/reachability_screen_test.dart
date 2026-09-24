import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/reachability_repository.dart';
import 'package:ha_phone_test/services/reachability_service.dart';
import 'package:ha_phone_test/services/ring_settings_repository.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/screens/reachability_screen.dart';
import 'package:ha_phone_test/widgets/app_nav_bar.dart';
import 'package:ha_phone_test/services/app_navigation.dart';

import '../helpers/fake_sip.dart';

Map<String, Object?> _snapshot({bool battery = true, bool exact = true, String oem = 'google'}) => {
      'notificationsEnabled': true,
      'canUseFullScreenIntent': true,
      'ignoringBatteryOptimizations': battery,
      'canScheduleExactAlarms': exact,
      'registered': true,
      'serviceRunning': true,
      'registrationState': 'registered',
      'lastRegisteredAt': DateTime(2026, 9, 24, 9, 41).millisecondsSinceEpoch,
      'manufacturer': oem,
      'oemFamily': oem,
      'sdkInt': 35,
    };

void main() {
  late FakeSip sip;
  late Map<String, Object?> snapshot;
  Map<Object?, Object?> ringPolicy = {};

  setUp(() {
    snapshot = _snapshot();
    ringPolicy = {'enabled': true, 'mutedUntil': 0, 'allowDoor': true};
    sip = FakeSip({
      'getReachability': (_) => snapshot,
      'openReachabilitySettings': (_) => true,
      'getRingPolicy': (_) => ringPolicy,
      'setRingPolicy': (args) => ringPolicy = Map<Object?, Object?>.from(args as Map),
    })
      ..install();
  });
  tearDown(() => sip.uninstall());

  Future<ReachabilityRepository> pump(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ring = RingSettingsRepository(clock: () => DateTime(2026, 9, 24, 10));
    final repo = ReachabilityRepository(service: ReachabilityService(), ring: ring);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: const Size(390, 844)),
        child: ReachabilityScreen(repository: repo, rttLoader: () async => 18, reconnect: () async {}),
      ),
    ));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('all ok: green summary, six checks, no Beheben, no OEM card on stock Android', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('reach-summary-ok')), findsOneWidget);
    expect(find.text('6 von 6 Punkten erfüllt. Anrufe kommen auch bei gesperrtem Handy.'), findsOneWidget);
    expect(find.text('angemeldet · 18 ms · zuletzt 9:41'), findsOneWidget);
    expect(find.text('Beheben'), findsNothing);
    expect(find.byKey(const Key('reach-oem')), findsNothing);
  });

  testWidgets('problems: amber summary, Beheben opens the settings page, refresh on resume', (tester) async {
    snapshot = _snapshot(battery: false, exact: false);
    final repo = await pump(tester);
    expect(find.byKey(const Key('reach-summary-warn')), findsOneWidget);
    expect(find.text('4 von 6 Punkten erfüllt. Tippe auf „Beheben“.'), findsOneWidget);
    expect(repo.hasProblems, isTrue);

    await tester.tap(find.byKey(const ValueKey('reach-fix-battery')));
    await tester.pump();
    expect(sip.callsTo('openReachabilitySettings').single.arguments, 'batteryOptimization');

    // User comes back from the settings page with the exemption granted.
    snapshot = _snapshot(exact: false);
    final before = sip.callsTo('getReachability').length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();
    expect(sip.callsTo('getReachability').length, greaterThan(before));
    expect(find.text('5 von 6 Punkten erfüllt. Tippe auf „Beheben“.'), findsOneWidget);
  });

  testWidgets('muted handset: Beheben switches ringing back on', (tester) async {
    ringPolicy = {'enabled': false, 'mutedUntil': 0, 'allowDoor': true};
    final repo = await pump(tester);
    expect(find.byKey(const ValueKey('reach-fix-ringing')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reach-fix-ringing')));
    await tester.pumpAndSettle();
    expect(ringPolicy['enabled'], true);
    expect(repo.hasProblems, isFalse);
  });

  testWidgets('Samsung: OEM card with steps and app settings link', (tester) async {
    snapshot = _snapshot(oem: 'samsung');
    await pump(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('reach-oem-open')), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const Key('reach-oem-open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nie in Standby versetzte Apps'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reach-oem-open')));
    await tester.pump();
    expect(sip.callsTo('openReachabilitySettings').last.arguments, 'appDetails');
  });

  testWidgets('textScale 2.0: no overflow', (tester) async {
    snapshot = _snapshot(battery: false, oem: 'xiaomi');
    await pump(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.byKey(const Key('reach-oem-open')), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const Key('reach-oem-open')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('nav bar shows the amber dot on Ich only when asked', (tester) async {
    Future<void> bar(bool warning) => tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(bottomNavigationBar: AppNavBar(selected: AppTab.start, onSelect: (_) {}, meWarning: warning)),
        ));
    await bar(false);
    expect(find.byKey(const ValueKey('warning-me')), findsNothing);
    await bar(true);
    expect(find.byKey(const ValueKey('warning-me')), findsOneWidget);
    expect(find.bySemanticsLabel('Ich, Erreichbarkeit prüfen'), findsOneWidget);
  });
}
