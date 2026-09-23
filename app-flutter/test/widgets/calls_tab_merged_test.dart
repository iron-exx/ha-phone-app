import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/screens/calls_tab.dart';
import 'package:ha_phone_test/services/call_history_store.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_sip.dart';

int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

void main() {
  late FakeSip sip;
  final now = DateTime.now();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
              startedAt: now.subtract(const Duration(hours: 2)),
            ),
          ],
    })
      ..install();
  });
  tearDown(() => sip.uninstall());

  FakePbx pbx() => FakePbx({
        'GET /api/mobile/calls': (_) => jsonResponse({
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
                  'started_at': _epoch(now) - 3600,
                  'duration_sec': 0,
                },
              ],
            }),
      });

  Future<CallHistoryStore> pump(WidgetTester tester) async {
    final fake = pbx();
    final store = CallHistoryStore(api: fake.api, authLoader: testAuthLoader);
    final dir = DirectoryRepository(api: fake.api, authLoader: testAuthLoader);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: CallsTab(isActive: false, store: store, directory: dir),
    ));
    await tester.runAsync(store.refreshAll);
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('merges PBX and local history into one list', (tester) async {
    await pump(tester);

    expect(find.text('türklingel'), findsOneWidget, reason: 'matched call is one row');
    expect(find.text('tuer'), findsNothing);
    expect(find.text('eingehend · 0:41'), findsOneWidget);
    expect(find.text('Pizzeria'), findsOneWidget);
    expect(find.text('verpasst · anderes Gerät'), findsOneWidget);
    expect(find.text('ausgehend · 0:05'), findsOneWidget);
  });

  testWidgets('Verpasst filter includes PBX-missed calls', (tester) async {
    final store = await pump(tester);
    expect(store.unseenMissed, 1);

    await tester.tap(find.text('Verpasst'));
    await tester.pumpAndSettle();
    expect(find.text('Pizzeria'), findsOneWidget);
    expect(find.text('türklingel'), findsNothing);
  });

  testWidgets('swiping a PBX-only row hides it without a native delete', (tester) async {
    await pump(tester);

    await tester.drag(find.text('Pizzeria'), const Offset(-500, 0));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();

    expect(find.text('Pizzeria'), findsNothing);
    expect(sip.callsTo('deleteCallHistoryEntry'), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('calls_hidden_pbx_v1'), ['p-desk']);
  });

  testWidgets('swiping a merged row deletes locally and hides the PBX entry', (tester) async {
    await pump(tester);

    await tester.drag(find.text('türklingel'), const Offset(-500, 0));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();

    expect(find.text('türklingel'), findsNothing);
    expect(find.text('tuer'), findsNothing);
    expect(sip.callsTo('deleteCallHistoryEntry').single.arguments, 'l1');
  });
}
