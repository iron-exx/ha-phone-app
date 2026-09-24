import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/screens/voicemail_tab.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/voicemail_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_audio.dart';
import '../helpers/fake_sip.dart';

final _now = DateTime.now();
int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

void main() {
  late FakeSip sip;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sip = FakeSip()..install();
  });
  tearDown(() => sip.uninstall());

  Map<String, Object?> filled() => {
        'messages': [
          {
            'id': 'INBOX/msg0000',
            'new': true,
            'caller_number': '0301234567',
            'caller_name': 'Pizzeria',
            'duration_sec': 42,
            'received_at': _epoch(DateTime(_now.year, _now.month, _now.day, 0, 5)),
          },
          {
            'id': 'Old/msg0000',
            'new': false,
            'caller_number': '11',
            'caller_name': '',
            'duration_sec': 7,
            'received_at': _epoch(DateTime(_now.year, _now.month, _now.day, 0, 1)),
          },
        ],
        'new_count': 1,
      };

  Future<({VoicemailRepository repo, FakeAudio audio})> pump(WidgetTester tester, FakePbx fake) async {
    final dir = DirectoryRepository(api: fake.api, authLoader: testAuthLoader);
    final repo = VoicemailRepository(api: fake.api, authLoader: testAuthLoader);
    final audio = FakeAudio();
    await tester.pumpWidget(MaterialApp(
      home: VoicemailTab(repository: repo, directory: dir, audioFactory: () => audio),
    ));
    await tester.runAsync(() async {
      await dir.refresh();
      await repo.refresh();
    });
    await tester.pumpAndSettle();
    return (repo: repo, audio: audio);
  }

  final directoryRoute = {
    'GET /api/mobile/directory': (_) => jsonResponse({
          'extensions': [
            {'number': '11', 'name': 'sandro'},
          ],
        }),
  };

  testWidgets('empty mailbox shows "Keine Nachrichten" and the *97 action', (tester) async {
    await pump(
        tester,
        FakePbx({
          ...directoryRoute,
          'GET /api/mobile/voicemail': (_) => jsonResponse({'messages': [], 'new_count': 0}),
        }));
    expect(find.text('Keine Nachrichten'), findsOneWidget);
    expect(find.byTooltip('Mailbox anrufen'), findsOneWidget);
  });

  testWidgets('filled mailbox: names, subtitle, new dot', (tester) async {
    await pump(tester, FakePbx({...directoryRoute, 'GET /api/mobile/voicemail': (_) => jsonResponse(filled())}));
    expect(find.text('Pizzeria'), findsOneWidget);
    expect(find.text('sandro'), findsOneWidget, reason: 'name resolved from the directory');
    expect(find.text('0:42 · heute 00:05'), findsOneWidget);
    expect(find.text('0:07 · heute 00:01'), findsOneWidget);
    expect(find.byKey(const ValueKey('voicemail-new-dot')), findsOneWidget);
  });

  testWidgets('tap expands the player; playing marks the message heard', (tester) async {
    final r =
        await pump(tester, FakePbx({...directoryRoute, 'GET /api/mobile/voicemail': (_) => jsonResponse(filled())}));

    await tester.tap(find.text('Pizzeria'));
    await tester.pumpAndSettle();
    expect(find.text('Zurückrufen'), findsOneWidget);
    expect(find.text('Löschen'), findsOneWidget);
    expect(find.text('0:00 / 0:42'), findsOneWidget);

    await tester.tap(find.byTooltip('Abspielen'));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();

    expect(r.audio.loaded.map((u) => u.path), ['/api/mobile/voicemail/INBOX/msg0000/audio']);
    expect(r.audio.plays, 1);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byKey(const ValueKey('voicemail-new-dot')), findsNothing);
    expect(r.repo.unheardCount, 0);
  });

  testWidgets('Löschen asks first, then deletes on the PBX', (tester) async {
    final fake = FakePbx({
      ...directoryRoute,
      'GET /api/mobile/voicemail': (_) => jsonResponse(filled()),
      'DELETE /api/mobile/voicemail/INBOX/msg0000': (_) => jsonResponse({'success': true}),
    });
    await pump(tester, fake);

    await tester.tap(find.text('Pizzeria'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Nachricht löschen?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();

    expect(fake.to('DELETE', '/api/mobile/voicemail/INBOX/msg0000'), hasLength(1));
    expect(find.text('Pizzeria'), findsNothing);
    expect(find.text('sandro'), findsOneWidget);
  });

  testWidgets('older PBX (404) shows the friendly update state', (tester) async {
    await pump(tester, FakePbx(directoryRoute));
    expect(find.textContaining('Funktion braucht HA-Phone 0.7.107 oder neuer'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Mailbox anrufen'), findsOneWidget);
  });
}
