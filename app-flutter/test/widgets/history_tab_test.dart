import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ha_phone_test/screens/history_tab.dart';
import 'package:ha_phone_test/services/app_navigation.dart';
import 'package:ha_phone_test/services/call_history_store.dart';
import 'package:ha_phone_test/services/call_launcher.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/presence_repository.dart';
import 'package:ha_phone_test/services/recordings_repository.dart';
import 'package:ha_phone_test/services/voicemail_repository.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/utils/timeline.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_audio.dart';
import '../helpers/fake_sip.dart';
import '../helpers/semantics.dart';

int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

class _Harness {
  _Harness(this.store, this.voicemail, this.recordings, this.audio, this.nav);

  final CallHistoryStore store;
  final VoicemailRepository voicemail;
  final RecordingsRepository recordings;
  final FakeAudio audio;
  final AppNavigation nav;
}

void main() {
  late FakeSip sip;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CallLauncher.requestMicrophone = () async => true;
    sip = FakeSip({
      'getCallHistory': (_) => [
            // Same call as PBX "p-same" (10 s apart): one row.
            historyEntry(id: 'l1', number: '16', name: 'türklingel', answered: true, durationSec: 41, startedAt: now),
            // PBX was offline for this one: local only.
            historyEntry(
              id: 'l2',
              number: '12',
              direction: 'outgoing',
              durationSec: 5,
              startedAt: now.subtract(const Duration(minutes: 2)),
            ),
          ],
    })
      ..install();
  });
  tearDown(() => sip.uninstall());

  Map<String, Object?> calls() => {
        'calls': [
          {
            'id': 'p-same',
            'number': '16',
            'name': 'tuer',
            'direction': 'incoming',
            'answered': true,
            'started_at': _epoch(now) - 10,
            'duration_sec': 40,
          },
          {
            'id': 'p-desk',
            'number': '0301234567',
            'name': 'Pizzeria',
            'direction': 'incoming',
            'answered': false,
            'started_at': _epoch(now) - 60,
            'duration_sec': 0,
          },
        ],
      };

  Map<String, Object?> voicemails() => {
        'messages': [
          {
            'id': 'INBOX/msg0000',
            'new': true,
            'caller_number': '0171555',
            'caller_name': 'Oma Erika',
            'duration_sec': 42,
            'received_at': _epoch(today.add(const Duration(minutes: 5))),
          },
        ],
        'new_count': 1,
      };

  FakePbx pbx({bool withVoicemail = true, bool withRecordings = true}) => FakePbx({
        'GET /api/mobile/calls': (_) => jsonResponse(calls()),
        'GET /api/mobile/directory': (_) => jsonResponse({
              'extensions': [
                {'number': '16', 'name': 'türklingel', 'door_open_code': '*1', 'video': true},
                {'number': '12', 'name': 'Büro'},
              ],
            }),
        if (withVoicemail) 'GET /api/mobile/voicemail': (_) => jsonResponse(voicemails()),
        'DELETE /api/mobile/voicemail/INBOX/msg0000': (_) => jsonResponse({'success': true}),
        if (withRecordings)
          'GET /api/mobile/recordings': (_) => jsonResponse({
                'allowed': true,
                'recordings': [
                  {
                    'id': '20260924-000100_12',
                    'peer': '12',
                    'started_at': _epoch(today.add(const Duration(minutes: 1))),
                    'duration_sec': 192,
                  },
                ],
              }),
      });

  Future<_Harness> pump(
    WidgetTester tester,
    FakePbx fake, {
    double textScale = 1,
    bool loadRecordings = true,
    Size size = const Size(390, 844),
  }) async {
    final store = CallHistoryStore(api: fake.api, authLoader: testAuthLoader);
    final dir = DirectoryRepository(api: fake.api, authLoader: testAuthLoader);
    final vm = VoicemailRepository(api: fake.api, authLoader: testAuthLoader);
    final rec = RecordingsRepository(api: fake.api, authLoader: testAuthLoader);
    final presence = PresenceRepository(api: fake.api, authLoader: testAuthLoader);
    final nav = AppNavigation();
    final audio = FakeAudio();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      routes: {'/active-call': (_) => const Scaffold(body: Text('ACTIVE'))},
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: size),
        child: HistoryTab(
          isActive: false,
          store: store,
          voicemail: vm,
          recordings: rec,
          directory: dir,
          presence: presence,
          navigation: nav,
          audioFactory: () => audio,
        ),
      ),
    ));
    await tester.runAsync(() async {
      await dir.refresh();
      await store.refreshAll();
      await vm.refresh();
      if (loadRecordings) await rec.refresh();
    });
    await tester.pumpAndSettle();
    return _Harness(store, vm, rec, audio, nav);
  }

  testWidgets('one timeline: calls (merged with the PBX log), voicemail, recording', (tester) async {
    await pump(tester, pbx());

    expect(find.text('HEUTE'), findsOneWidget);
    expect(find.text('türklingel'), findsOneWidget, reason: 'matched call is one row');
    expect(find.text('tuer'), findsNothing);
    expect(find.text('eingehend · 0:41'), findsOneWidget);
    expect(find.text('Pizzeria'), findsOneWidget);
    expect(find.text('verpasst · anderes Gerät'), findsOneWidget);
    expect(find.text('ausgehend · 0:05'), findsOneWidget);
    expect(find.text('Oma Erika'), findsOneWidget);
    expect(find.text('Sprachnachricht · 0:42'), findsOneWidget);
    expect(find.text('Aufnahme · 3:12'), findsOneWidget);
    // Unread: the PBX-missed call and the new voicemail carry the bar.
    expect(find.byKey(const ValueKey('unread-bar')), findsNWidgets(2));
    // Door station rows use the door symbol.
    expect(find.byIcon(Icons.door_front_door_outlined), findsWidgets);
  });

  testWidgets('filter chips: Verpasst with count, Voicemail, Aufnahmen, Tür', (tester) async {
    await pump(tester, pbx());
    expect(find.text('Verpasst · 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('filter-missed')));
    await tester.pumpAndSettle();
    expect(find.text('Pizzeria'), findsOneWidget);
    expect(find.text('türklingel'), findsNothing);
    expect(find.text('Oma Erika'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('filter-voicemail')));
    await tester.pumpAndSettle();
    expect(find.text('Oma Erika'), findsOneWidget);
    expect(find.text('Pizzeria'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('filter-recordings')));
    await tester.pumpAndSettle();
    expect(find.text('Aufnahme · 3:12'), findsOneWidget);
    expect(find.text('Büro'), findsOneWidget, reason: 'recording peer resolved from the directory');

    await tester.tap(find.byKey(const ValueKey('filter-door')));
    await tester.pumpAndSettle();
    expect(find.text('türklingel'), findsOneWidget);
    expect(find.text('Pizzeria'), findsNothing);
  });

  testWidgets('swiping a PBX-only call left hides it without a native delete', (tester) async {
    await pump(tester, pbx());

    await tester.drag(find.text('Pizzeria'), const Offset(-500, 0));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();

    expect(find.text('Pizzeria'), findsNothing);
    expect(sip.callsTo('deleteCallHistoryEntry'), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('calls_hidden_pbx_v1'), ['p-desk']);
  });

  testWidgets('swiping a merged call left deletes locally and hides the PBX entry', (tester) async {
    await pump(tester, pbx());

    await tester.drag(find.text('türklingel'), const Offset(-500, 0));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();

    expect(find.text('türklingel'), findsNothing);
    expect(find.text('tuer'), findsNothing);
    expect(sip.callsTo('deleteCallHistoryEntry').single.arguments, 'l1');
  });

  testWidgets('swiping right calls back and keeps the row', (tester) async {
    await pump(tester, pbx());

    await tester.drag(find.text('Pizzeria'), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(sip.callsTo('makeCall').single.arguments, '0301234567');
    expect(find.text('ACTIVE'), findsOneWidget);
    Navigator.of(tester.element(find.text('ACTIVE'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Pizzeria'), findsOneWidget);
  });

  testWidgets('inline voicemail player: play marks heard, speed chip cycles', (tester) async {
    final h = await pump(tester, pbx());

    await tester.tap(find.byKey(const ValueKey('filter-voicemail')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('unread-bar')), findsOneWidget);

    await tester.tap(find.byTooltip('Abspielen'));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();

    expect(h.audio.loaded.map((u) => u.path), ['/api/mobile/voicemail/INBOX/msg0000/audio']);
    expect(h.audio.plays, 1);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(h.voicemail.unheardCount, 0);
    expect(find.byKey(const ValueKey('unread-bar')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('player-speed')));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();
    expect(find.text('1,5×'), findsOneWidget);
    expect(h.audio.speed, 1.5);
  });

  testWidgets('swiping a voicemail left asks first, then deletes it on the PBX', (tester) async {
    final fake = pbx();
    await pump(tester, fake);

    await tester.drag(find.text('Oma Erika'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Sprachnachricht löschen?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();

    expect(fake.to('DELETE', '/api/mobile/voicemail/INBOX/msg0000'), hasLength(1));
    expect(find.text('Oma Erika'), findsNothing);
  });

  testWidgets('cancelling the delete dialog keeps the voicemail', (tester) async {
    final fake = pbx();
    await pump(tester, fake);

    await tester.drag(find.text('Oma Erika'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(fake.to('DELETE', '/api/mobile/voicemail/INBOX/msg0000'), isEmpty);
    expect(find.text('Oma Erika'), findsOneWidget);
  });

  testWidgets('TalkBack "Löschen" on a voicemail asks first too', (tester) async {
    final handle = tester.ensureSemantics();
    final fake = pbx();
    await pump(tester, fake);
    await tester.tap(find.byKey(const ValueKey('filter-voicemail')));
    await tester.pumpAndSettle();

    semanticsCustomAction(tester, 'Löschen');
    await tester.pumpAndSettle();
    expect(find.text('Sprachnachricht löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(fake.to('DELETE', '/api/mobile/voicemail/INBOX/msg0000'), isEmpty);

    semanticsCustomAction(tester, 'Löschen');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();
    expect(fake.to('DELETE', '/api/mobile/voicemail/INBOX/msg0000'), hasLength(1));
    handle.dispose();
  });

  testWidgets('Aufnahmen before the first load: spinner, not "nicht freigegeben"', (tester) async {
    await pump(tester, pbx(), loadRecordings: false);
    await tester.tap(find.byKey(const ValueKey('filter-recordings')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('nicht freigegeben'), findsNothing);
  });

  testWidgets('PBX unreachable after a load: "Anlage nicht erreichbar – Stand hh:mm"', (tester) async {
    final fake = pbx();
    final h = await pump(tester, fake);
    final at = h.store.pbxLoadedAt!;
    fake.routes['GET /api/mobile/calls'] = (_) => throw http.ClientException('offline');
    await tester.runAsync(h.store.refreshPbx);
    await tester.pumpAndSettle();
    final hhmm = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    expect(find.text('Anlage nicht erreichbar – Stand $hhmm'), findsOneWidget);
    expect(find.text('Pizzeria'), findsOneWidget, reason: 'last known PBX entries stay');
  });

  testWidgets('Voicemail filter on an older PBX shows the update hint and *97', (tester) async {
    await pump(tester, pbx(withVoicemail: false));
    await tester.tap(find.byKey(const ValueKey('filter-voicemail')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Funktion braucht HA-Phone 0.7.107 oder neuer'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Mailbox anrufen'), findsOneWidget);
  });

  testWidgets('navigation request selects the Voicemail filter', (tester) async {
    final h = await pump(tester, pbx());
    h.nav.openHistory(TimelineFilter.voicemail);
    await tester.pumpAndSettle();

    expect(find.text('Oma Erika'), findsOneWidget);
    expect(find.text('Pizzeria'), findsNothing);
  });

  testWidgets('search narrows the timeline', (tester) async {
    await pump(tester, pbx());
    await tester.tap(find.byTooltip('Verlauf durchsuchen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pizz');
    await tester.pumpAndSettle();

    expect(find.text('Pizzeria'), findsOneWidget);
    expect(find.text('türklingel'), findsNothing);
  });

  testWidgets('no overflow at 200 % text size', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, pbx(), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Pizzeria'), findsOneWidget);
  });

  testWidgets('no overflow at 200 % text size on a 320 dp phone, every filter', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, pbx(), textScale: 2, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    for (final f in TimelineFilter.values) {
      final chip = find.byKey(ValueKey('filter-${f.name}'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: f.name);
    }
  });
}
