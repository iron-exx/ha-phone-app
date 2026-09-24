import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/screens/forwarding_screen.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/forwarding_repository.dart';
import 'package:ha_phone_test/services/presence_repository.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_sip.dart';

const _ringGroupRule = {
  'status': 'away',
  'direction': 'internal',
  'mode': 'ring_then_dest',
  'dest_type': 'ring_group',
  'dest_target': 3,
  'ring_timeout': 25,
};

const _lunchRule = {
  'status': 'lunch',
  'direction': 'internal',
  'mode': 'ring_then_dest',
  'dest_type': 'extension',
  'dest_target': 11,
  'ring_timeout': 20,
};

void main() {
  late FakeSip sip;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sip = FakeSip()..install();
  });
  tearDown(() => sip.uninstall());

  FakePbx pbx({int putStatus = 200}) => FakePbx({
        'GET /api/mobile/directory': (_) => jsonResponse({
              'self': {'number': '13', 'name': 'Test', 'presence': 'lunch'},
              'extensions': [
                {'number': '13', 'name': 'Test'},
                {'number': '11', 'name': 'sandro'},
              ],
            }),
        'GET /api/mobile/presence': (_) => jsonResponse({
              'self': {'number': '13', 'presence': 'lunch', 'line': 'idle'},
              'extensions': [],
            }),
        'GET /api/mobile/forwarding': (_) => jsonResponse({
              'rules': [_ringGroupRule, _lunchRule],
            }),
        'PUT /api/mobile/forwarding': (req) =>
            putStatus == 200 ? jsonResponse(jsonDecode(req.body) as Object) : jsonResponse({'detail': 'x'}, putStatus),
      });

  Future<void> pump(WidgetTester tester, FakePbx fake) async {
    final dir = DirectoryRepository(api: fake.api, authLoader: testAuthLoader);
    final pres = PresenceRepository(api: fake.api, authLoader: testAuthLoader);
    final repo = ForwardingRepository(api: fake.api, authLoader: testAuthLoader);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: ForwardingScreen(repository: repo, directory: dir, presence: pres),
    ));
    await tester.runAsync(() async {
      await dir.refresh();
      await pres.refresh();
      await repo.refresh();
    });
    await tester.pumpAndSettle();
  }

  Finder row(String status, String direction) => find.byKey(ValueKey('forward-$status-$direction'));

  Future<void> tapRow(WidgetTester tester, String status, String direction) async {
    await tester.ensureVisible(row(status, direction));
    await tester.pumpAndSettle();
    await tester.tap(row(status, direction));
    await tester.pumpAndSettle();
  }

  testWidgets('shows plain-German behaviour per status and marks the own status', (tester) async {
    await pump(tester, pbx());

    expect(find.descendant(of: row('lunch', 'internal'), matching: find.text('Nach 20 s zu 11 · sandro')),
        findsOneWidget);
    expect(find.descendant(of: row('lunch', 'external'), matching: find.text('Normal klingeln')), findsOneWidget);
    expect(find.descendant(of: row('away', 'internal'), matching: find.text('Nach 25 s zur Klingelgruppe')),
        findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('forward-card-lunch')), matching: find.text('Aktiv')),
      findsOneWidget,
    );
    expect(find.text('Aktiv'), findsOneWidget);
  });

  testWidgets('edit → "Sofort …" Mailbox PUTs the full list, ring group untouched', (tester) async {
    final fake = pbx();
    await pump(tester, fake);

    await tapRow(tester, 'lunch', 'external');
    expect(find.text('Mittagspause · Externe Anrufe'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('forward-mode-always')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();

    final put = fake.to('PUT', '/api/mobile/forwarding').single;
    final rules = (jsonDecode(put.body) as Map<String, dynamic>)['rules'] as List;
    expect(rules, [
      _ringGroupRule,
      _lunchRule,
      {
        'status': 'lunch',
        'direction': 'external',
        'mode': 'always_dest',
        'dest_type': 'voicemail',
        'dest_target': 13,
        'ring_timeout': 20,
      },
    ]);
    expect(find.descendant(of: row('lunch', 'external'), matching: find.text('Sofort zur Mailbox')), findsOneWidget);
  });

  testWidgets('status cards use presence glyphs (colour + shape)', (tester) async {
    await pump(tester, pbx());
    for (final status in ['available', 'away', 'do_not_disturb']) {
      final glyph = find.byKey(ValueKey('forward-glyph-$status'));
      await tester.scrollUntilVisible(glyph, 150);
      expect(find.descendant(of: glyph, matching: find.byType(Icon)), findsOneWidget, reason: status);
    }
  });

  testWidgets('ring timeout slider: 5–120 s, spoken in Sekunden', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, pbx());
    await tapRow(tester, 'lunch', 'internal');
    final slider = tester.widget<Slider>(find.byKey(const ValueKey('forward-timeout')));
    expect(slider.min, 5);
    expect(slider.max, 120);
    expect(tester.getSemantics(find.byKey(const ValueKey('forward-timeout'))).value, '20 Sekunden');
    handle.dispose();
  });

  testWidgets('"Normal klingeln" removes the rule', (tester) async {
    final fake = pbx();
    await pump(tester, fake);

    await tapRow(tester, 'lunch', 'internal');
    await tester.tap(find.byKey(const ValueKey('forward-mode-normal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();

    final rules = (jsonDecode(fake.to('PUT', '/api/mobile/forwarding').single.body) as Map)['rules'] as List;
    expect(rules, [_ringGroupRule]);
  });

  testWidgets('ring-group rows are read-only', (tester) async {
    final fake = pbx();
    await pump(tester, fake);

    await tapRow(tester, 'away', 'internal');
    expect(find.text('Speichern'), findsNothing);
    expect(find.textContaining('nur in der Anlage'), findsOneWidget);
    expect(fake.to('PUT', '/api/mobile/forwarding'), isEmpty);
  });

  testWidgets('rejected save reverts and shows a SnackBar', (tester) async {
    await pump(tester, pbx(putStatus: 422));

    await tapRow(tester, 'lunch', 'external');
    await tester.tap(find.byKey(const ValueKey('forward-mode-always')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('forward-dest-hangup')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();

    expect(find.textContaining('Weiterleitung nicht gespeichert'), findsOneWidget);
    expect(find.descendant(of: row('lunch', 'external'), matching: find.text('Normal klingeln')), findsOneWidget);
  });

  testWidgets('older PBX shows the 0.7.110 hint', (tester) async {
    await pump(tester, FakePbx({}));
    expect(find.text('Funktion braucht HA-Phone 0.7.110 oder neuer.'), findsOneWidget);
  });
}
