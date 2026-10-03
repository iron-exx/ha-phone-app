import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/reachability_repository.dart';
import 'package:ha_phone_test/services/reachability_service.dart';
import 'package:ha_phone_test/services/ring_settings_repository.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/widgets/call_visibility_banner.dart';

import '../helpers/fake_sip.dart';

Map<String, Object?> _snapshot({bool notifications = true, bool fullScreen = true, bool battery = true}) => {
      'notificationsEnabled': notifications,
      'canUseFullScreenIntent': fullScreen,
      'ignoringBatteryOptimizations': battery,
      'canScheduleExactAlarms': true,
      'registered': true,
      'serviceRunning': true,
      'sdkInt': 36,
    };

void main() {
  late FakeSip sip;
  late Map<String, Object?> snapshot;
  late List<Object?> opened;

  setUp(() {
    snapshot = _snapshot();
    opened = [];
    sip = FakeSip({
      'getReachability': (_) => snapshot,
      'openReachabilitySettings': (page) {
        opened.add(page);
        return true;
      },
      'getRingPolicy': (_) => {'enabled': true, 'mutedUntil': 0, 'allowDoor': true},
    })
      ..install();
  });
  tearDown(() => sip.uninstall());

  Future<void> pump(WidgetTester tester) async {
    final repo = ReachabilityRepository(
        service: ReachabilityService(), ring: RingSettingsRepository(clock: () => DateTime(2026, 10, 3, 10)));
    await tester.runAsync(repo.refresh);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: CallVisibilityBanner(reachability: repo)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('nothing shown while calls can appear', (tester) async {
    snapshot = _snapshot(battery: false); // other issues stay on the Erreichbarkeit screen
    await pump(tester);
    expect(find.byKey(const Key('call-visibility-banner')), findsNothing);
  });

  testWidgets('missing full-screen permission: warning with a button to the right settings page', (tester) async {
    snapshot = _snapshot(fullScreen: false);
    await pump(tester);
    expect(find.byKey(const Key('call-visibility-banner')), findsOneWidget);
    expect(find.textContaining('Vollbild'), findsWidgets);
    await tester.tap(find.text('Erlauben'));
    await tester.runAsync(() => pumpEventQueue());
    expect(opened, ['fullScreenIntent']);
  });

  testWidgets('notifications off wins: without them nothing appears at all', (tester) async {
    snapshot = _snapshot(notifications: false, fullScreen: false);
    await pump(tester);
    expect(find.textContaining('Benachrichtigungen'), findsWidgets);
    await tester.tap(find.text('Erlauben'));
    await tester.runAsync(() => pumpEventQueue());
    expect(opened, ['notifications']);
  });
}
