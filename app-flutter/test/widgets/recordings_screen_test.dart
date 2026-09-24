import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/screens/me_tab.dart';
import 'package:ha_phone_test/screens/recordings_screen.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/recordings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_audio.dart';
import '../helpers/fake_sip.dart';

final _now = DateTime.now();
int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

Map<String, Object?> _recording(String id, String peer, int durationSec, DateTime at) =>
    {'id': id, 'peer': peer, 'started_at': _epoch(at), 'duration_sec': durationSec, 'size_bytes': 1000};

Map<String, Object?> _filled() => {
      'allowed': true,
      'recordings': [
        _recording('20260924-000500_0301234567', '0301234567', 192,
            DateTime(_now.year, _now.month, _now.day, 0, 5)),
        _recording('20260924-000100_11', '11', 7, DateTime(_now.year, _now.month, _now.day, 0, 1)),
        _recording('20260924-000000_', '', 3, DateTime(_now.year, _now.month, _now.day, 0, 0)),
      ],
    };

final _directoryRoute = {
  'GET /api/mobile/directory': (_) => jsonResponse({
        'self': {'number': '12', 'name': 'App', 'recording_allowed': true},
        'extensions': [
          {'number': '11', 'name': 'sandro'},
        ],
        'phonebook': [
          {'number': '0301234567', 'name': 'Pizzeria'},
        ],
      }),
};

void main() {
  late FakeSip sip;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sip = FakeSip({
      'getRegistrationState': (_) => 'registered',
      'getDeviceAuth': (_) => <String, String>{},
    })
      ..install();
  });
  tearDown(() => sip.uninstall());

  group('RecordingsScreen', () {
    Future<FakeAudio> pump(WidgetTester tester, FakePbx fake) async {
      final dir = DirectoryRepository(api: fake.api, authLoader: testAuthLoader);
      final repo = RecordingsRepository(api: fake.api, authLoader: testAuthLoader);
      final audio = FakeAudio();
      await tester.runAsync(dir.refresh);
      await tester.pumpWidget(MaterialApp(
        home: RecordingsScreen(repository: repo, directory: dir, audioFactory: () => audio),
      ));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      return audio;
    }

    testWidgets('lists recordings with resolved names, duration and time', (tester) async {
      await pump(tester, FakePbx({..._directoryRoute, 'GET /api/mobile/recordings': (_) => jsonResponse(_filled())}));
      expect(find.text('Pizzeria'), findsOneWidget, reason: 'phonebook name');
      expect(find.text('sandro'), findsOneWidget, reason: 'extension name');
      expect(find.text('Unbekannt'), findsOneWidget, reason: 'no peer');
      expect(find.text('3:12 · heute 00:05'), findsOneWidget);
      expect(find.text('0:07 · heute 00:01'), findsOneWidget);
    });

    testWidgets('tap expands the player and plays the recording', (tester) async {
      final audio =
          await pump(tester, FakePbx({..._directoryRoute, 'GET /api/mobile/recordings': (_) => jsonResponse(_filled())}));
      await tester.tap(find.text('sandro'));
      await tester.pumpAndSettle();
      expect(find.text('Zurückrufen'), findsOneWidget);
      expect(find.text('0:00 / 0:07'), findsOneWidget);

      await tester.tap(find.byTooltip('Abspielen'));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      expect(audio.loaded.map((u) => u.path), ['/api/mobile/recordings/20260924-000100_11/audio']);
      expect(audio.plays, 1);
      expect(find.byTooltip('Pause'), findsOneWidget);
    });

    testWidgets('Löschen asks first, then deletes on the PBX', (tester) async {
      final fake = FakePbx({
        ..._directoryRoute,
        'GET /api/mobile/recordings': (_) => jsonResponse(_filled()),
        'DELETE /api/mobile/recordings/20260924-000100_11': (_) => jsonResponse({'success': true}),
      });
      await pump(tester, fake);
      await tester.tap(find.text('sandro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();
      expect(find.text('Aufnahme löschen?'), findsOneWidget);
      expect(find.text('Die Aufnahme des Gesprächs mit sandro wird auf der Anlage gelöscht.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      expect(fake.to('DELETE', '/api/mobile/recordings/20260924-000100_11'), hasLength(1));
      expect(find.text('sandro'), findsNothing);
      expect(find.text('Pizzeria'), findsOneWidget);
    });

    testWidgets('pull to refresh reloads the list', (tester) async {
      final fake = FakePbx({..._directoryRoute, 'GET /api/mobile/recordings': (_) => jsonResponse(_filled())});
      await pump(tester, fake);
      expect(fake.to('GET', '/api/mobile/recordings'), hasLength(1));
      await tester.fling(find.text('Pizzeria'), const Offset(0, 400), 1000);
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      expect(fake.to('GET', '/api/mobile/recordings'), hasLength(2));
    });

    testWidgets('empty list explains how to record', (tester) async {
      await pump(
          tester,
          FakePbx({
            ..._directoryRoute,
            'GET /api/mobile/recordings': (_) => jsonResponse({'allowed': true, 'recordings': []}),
          }));
      expect(find.text('Keine Aufnahmen\nIm Gespräch auf „Aufnehmen“ tippen.'), findsOneWidget);
    });

    testWidgets('older PBX (404) shows the update hint', (tester) async {
      await pump(tester, FakePbx(_directoryRoute));
      expect(find.text('Funktion braucht HA-Phone 0.7.114 oder neuer.'), findsOneWidget);
    });
  });

  group('Ich tab entry', () {
    Future<void> pumpMe(WidgetTester tester, {required bool allowed, List<Object?> recordings = const []}) async {
      final fake = FakePbx({
        'GET /api/mobile/directory': (_) => jsonResponse({
              'self': {'number': '12', 'name': 'App', 'recording_allowed': allowed},
            }),
        'GET /api/mobile/recordings': (_) => jsonResponse({'allowed': allowed, 'recordings': recordings}),
      });
      final dir = DirectoryRepository(api: fake.api, authLoader: testAuthLoader);
      final repo = RecordingsRepository(api: fake.api, authLoader: testAuthLoader);
      await tester.runAsync(() async {
        await dir.refresh();
        await repo.refresh();
      });
      await tester.pumpWidget(MaterialApp(
        home: MeTab(onSetupChanged: () async {}, onUnpaired: () async {}, recordings: repo, directory: dir),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shown while recording is allowed, opens the list', (tester) async {
      await pumpMe(tester, allowed: true);
      expect(find.text('Aufnahmen'), findsOneWidget);
      expect(find.text('Keine Aufnahmen'), findsOneWidget);

      await tester.tap(find.text('Aufnahmen'));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      expect(find.text('Keine Aufnahmen\nIm Gespräch auf „Aufnehmen“ tippen.'), findsOneWidget);
    });

    testWidgets('hidden when not allowed and nothing was recorded', (tester) async {
      await pumpMe(tester, allowed: false);
      expect(find.byKey(const Key('me-recordings')), findsNothing);
    });

    testWidgets('still shown for old recordings after the admin disabled recording', (tester) async {
      await pumpMe(tester, allowed: false, recordings: [
        _recording('20260924-000100_11', '11', 7, _now),
      ]);
      expect(find.byKey(const Key('me-recordings')), findsOneWidget);
      expect(find.text('1 Aufnahme'), findsOneWidget);
    });
  });
}
