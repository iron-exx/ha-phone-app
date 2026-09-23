import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/presence_repository.dart';
import 'package:ha_phone_test/widgets/own_status_header.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_sip.dart';

void main() {
  late FakeSip sip;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sip = FakeSip()..install();
  });
  tearDown(() => sip.uninstall());

  FakePbx pbx({int putStatus = 200}) => FakePbx({
        'GET /api/mobile/directory': (_) => jsonResponse({
              'self': {'number': '12', 'name': 'Anna', 'presence': 'available'},
              'extensions': [],
              'phonebook': [],
            }),
        'GET /api/mobile/presence': (_) => jsonResponse({
              'self': {'number': '12', 'presence': 'available', 'line': 'busy'},
              'extensions': [],
            }),
        'PUT /api/mobile/presence': (req) => putStatus == 200
            ? jsonResponse({'number': '12', 'presence': (jsonDecode(req.body) as Map)['status']})
            : http.Response('', putStatus),
      });

  Future<PresenceRepository> pump(WidgetTester tester, FakePbx fake) async {
    final dir = DirectoryRepository(api: fake.api, authLoader: testAuthLoader);
    final presence = PresenceRepository(api: fake.api, authLoader: testAuthLoader);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: OwnStatusHeader(directory: dir, presence: presence)),
    ));
    await tester.runAsync(() async {
      await dir.refresh();
      await presence.refresh();
    });
    await tester.pumpAndSettle();
    return presence;
  }

  testWidgets('shows own presence and line state', (tester) async {
    await pump(tester, pbx());
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('verfügbar'), findsOneWidget);
    expect(find.text('Leitung: telefoniert'), findsOneWidget);
    expect(find.text('Status ändern folgt'), findsNothing);
  });

  testWidgets('chip opens the sheet; picking a status PUTs it', (tester) async {
    final fake = pbx();
    final presence = await pump(tester, fake);

    await tester.tap(find.text('verfügbar'));
    await tester.pumpAndSettle();
    expect(find.text('Status wählen'), findsOneWidget);
    for (final label in ['verfügbar', 'abwesend', 'Mittagspause', 'nicht stören', 'Feierabend']) {
      expect(find.widgetWithText(ListTile, label), findsOneWidget);
    }
    expect(
      find.descendant(of: find.byKey(const ValueKey('presence-available')), matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );

    await tester.tap(find.text('Mittagspause'));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();

    expect(find.text('Status wählen'), findsNothing);
    expect(find.text('Mittagspause'), findsOneWidget);
    expect(jsonDecode(fake.to('PUT', '/api/mobile/presence').single.body), {'status': 'lunch'});
    expect(presence.snapshot?.self?.presence.apiValue, 'lunch');
  });

  testWidgets('failed PUT reverts the chip and shows a SnackBar', (tester) async {
    await pump(tester, pbx(putStatus: 500));

    await tester.tap(find.text('verfügbar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('abwesend'));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();

    expect(find.text('verfügbar'), findsOneWidget);
    expect(find.textContaining('Status nicht gespeichert'), findsOneWidget);
  });

  testWidgets('older PBX shows the update hint', (tester) async {
    final fake = FakePbx({
      'GET /api/mobile/directory': (_) => jsonResponse({
            'self': {'number': '12', 'name': 'Anna', 'presence': 'away'},
          }),
    });
    await pump(tester, fake);
    expect(find.text('abwesend'), findsOneWidget);
    expect(find.text('Funktion braucht HA-Phone 0.7.107 oder neuer.'), findsOneWidget);
  });
}
