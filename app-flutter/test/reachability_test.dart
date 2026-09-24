import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/reachability.dart';
import 'package:ha_phone_test/services/reachability_service.dart';

import 'helpers/fake_sip.dart';

Map<String, Object?> _healthy() => {
      'notificationsEnabled': true,
      'canUseFullScreenIntent': true,
      'ignoringBatteryOptimizations': true,
      'canScheduleExactAlarms': true,
      'registered': true,
      'serviceRunning': true,
      'registrationState': 'registered',
      'lastRegisteredAt': 1790000000000,
      'registrationExpiresAt': 1790000600000,
      'lastWakeupAt': 1789999520000,
      'lastTransportDropAt': null,
      'nextAlarmAt': 1790000480000,
      'manufacturer': 'samsung',
      'oemFamily': 'samsung',
      'sdkInt': 35,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReachabilitySnapshot.fromMap', () {
    test('parses flags, timestamps and OEM', () {
      final s = ReachabilitySnapshot.fromMap(_healthy());
      expect(s.registered, isTrue);
      expect(s.registrationState, 'registered');
      expect(s.lastRegisteredAt, DateTime.fromMillisecondsSinceEpoch(1790000000000));
      expect(s.registrationExpiresAt!.difference(s.lastRegisteredAt!), const Duration(minutes: 10));
      expect(s.lastWakeupAt, isNotNull);
      expect(s.lastTransportDropAt, isNull);
      expect(s.oemFamily, OemFamily.samsung);
      expect(s.manufacturer, 'samsung');
      expect(s.sdkInt, 35);
      expect(s.issues, isEmpty);
      expect(s.isFullyReachable, isTrue);
    });

    test('missing or unknown values are safe defaults', () {
      final s = ReachabilitySnapshot.fromMap(const {'oemFamily': 'nokia'});
      expect(s.oemFamily, OemFamily.other);
      expect(s.registrationState, 'unknown');
      expect(s.lastRegisteredAt, isNull);
      expect(s.sdkInt, 0);
      expect(s.isFullyReachable, isFalse);
    });

    test('issues are listed in order and point at the right settings page', () {
      final s = ReachabilitySnapshot.fromMap({
        ..._healthy(),
        'notificationsEnabled': false,
        'ignoringBatteryOptimizations': false,
        'canScheduleExactAlarms': false,
        'registered': false,
      });
      expect(s.issues, [
        ReachabilityIssue.notificationsDisabled,
        ReachabilityIssue.batteryOptimized,
        ReachabilityIssue.exactAlarmsDenied,
        ReachabilityIssue.notRegistered,
      ]);
      expect(s.issues.map((i) => i.settingsPage), [
        ReachabilitySettingsPage.notifications,
        ReachabilitySettingsPage.batteryOptimization,
        ReachabilitySettingsPage.exactAlarm,
        null,
      ]);
    });

    test('full-screen-intent and stopped service are issues too', () {
      final s = ReachabilitySnapshot.fromMap({..._healthy(), 'canUseFullScreenIntent': false, 'serviceRunning': false});
      expect(s.issues, [ReachabilityIssue.fullScreenIntentDenied, ReachabilityIssue.serviceStopped]);
      expect(ReachabilityIssue.fullScreenIntentDenied.settingsPage, ReachabilitySettingsPage.fullScreenIntent);
    });
  });

  group('ReachabilityService', () {
    FakeSip? fake;

    tearDown(() {
      fake?.uninstall();
      fake = null;
    });

    FakeSip install(Map<String, Object? Function(Object? args)> responses) => fake = FakeSip(responses)..install();

    test('load() reads getReachability', () async {
      final sip = install({'getReachability': (_) => _healthy()});
      final s = await ReachabilityService().load();
      expect(s, isNotNull);
      expect(s!.isFullyReachable, isTrue);
      expect(sip.callsTo('getReachability'), hasLength(1));
    });

    test('load() returns null when the native side fails', () async {
      install({'getReachability': (_) => throw PlatformException(code: 'SIP_ERROR')});
      expect(await ReachabilityService().load(), isNull);
    });

    test('openSettings sends the page key', () async {
      final sip = install({'openReachabilitySettings': (_) => true});
      final opened = await ReachabilityService().openSettings(ReachabilitySettingsPage.exactAlarm);
      expect(opened, isTrue);
      expect(sip.callsTo('openReachabilitySettings').single.arguments, 'exactAlarm');
    });

    test('openSettings keys match the native ReachSettings.Target keys', () {
      expect(ReachabilitySettingsPage.values.map((p) => p.name),
          ['exactAlarm', 'batteryOptimization', 'fullScreenIntent', 'notifications', 'appDetails']);
    });

    test('openSettings is false when nothing could be opened', () async {
      install({'openReachabilitySettings': (_) => false});
      expect(await ReachabilityService().openSettings(ReachabilitySettingsPage.appDetails), isFalse);
    });
  });
}
