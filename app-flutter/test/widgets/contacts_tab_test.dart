import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/screens/contacts_tab.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/presence_repository.dart';
import 'package:ha_phone_test/theme/app_colors.dart';
import 'package:ha_phone_test/widgets/contact_avatar.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_sip.dart';

const _body = {
  'self': {'number': '13', 'name': 'Test', 'presence': 'available'},
  'extensions': [
    {'number': '13', 'name': 'Test', 'presence': 'available'},
    {'number': '11', 'name': 'sandro', 'presence': 'lunch'},
    {'number': '16', 'name': 'türklingel', 'video': true, 'door_open_code': '*1', 'presence': 'available'},
  ],
  'phonebook': [
    {'number': '0301234567', 'name': 'Pizzeria'},
  ],
};

void main() {
  late FakeSip sip;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sip = FakeSip()..install();
  });
  tearDown(() => sip.uninstall());

  DirectoryRepository repo(http.Response response) => DirectoryRepository(
        api: ApiClient(client: MockClient((_) async => response)),
        authLoader: () async => const DeviceAuth(apiHost: 'box', deviceId: '1', deviceToken: 't'),
      );

  Future<void> pumpTab(WidgetTester tester, DirectoryRepository r) async {
    await tester.pumpWidget(MaterialApp(home: ContactsTab(repository: r)));
    await tester.runAsync(r.init);
    await tester.pumpAndSettle();
  }

  testWidgets('lists extensions with presence, door icon, without self', (tester) async {
    final r = repo(http.Response.bytes(utf8.encode(jsonEncode(_body)), 200));
    await pumpTab(tester, r);

    expect(find.text('11 · Mittagspause'), findsOneWidget);
    expect(find.text('16 · verfügbar'), findsOneWidget);
    expect(find.text('Test'), findsNothing);
    expect(find.byIcon(Icons.door_front_door_outlined), findsOneWidget);
    expect(sip.callsTo('setDoorCodes').single.arguments, {'16': '*1'});
  });

  testWidgets('search and phonebook segment', (tester) async {
    final r = repo(http.Response.bytes(utf8.encode(jsonEncode(_body)), 200));
    await pumpTab(tester, r);

    await tester.enterText(find.byType(TextField), 'sand');
    await tester.pump();
    expect(find.text('sandro'), findsOneWidget);
    expect(find.text('türklingel'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Telefonbuch'));
    await tester.pumpAndSettle();
    expect(find.text('Pizzeria'), findsOneWidget);
    expect(find.text('sandro'), findsNothing);
  });

  testWidgets('401 shows a re-pair banner', (tester) async {
    await pumpTab(tester, repo(http.Response('', 401)));
    expect(find.textContaining('Gerät neu koppeln'), findsOneWidget);
    expect(find.text('Neu koppeln'), findsOneWidget);
  });

  testWidgets('live line state wins over presence, merged by number', (tester) async {
    final pbx = FakePbx({
      'GET /api/mobile/directory': (_) => jsonResponse({
            ..._body,
            'extensions': [
              ...(_body['extensions'] as List),
              {'number': '15', 'name': 'Büro', 'presence': 'available'},
              {'number': '17', 'name': 'Lager', 'presence': 'available'},
            ],
          }),
      'GET /api/mobile/presence': (_) => jsonResponse({
            'self': {'number': '13', 'presence': 'available', 'line': 'idle'},
            'extensions': [
              {'number': '11', 'presence': 'lunch', 'line': 'busy'},
              {'number': '15', 'presence': 'available', 'line': 'offline'},
              {'number': '16', 'presence': 'available', 'line': 'ringing'},
              {'number': '17', 'presence': 'lunch', 'line': 'idle'},
            ],
          }),
    });
    final dir = DirectoryRepository(api: pbx.api, authLoader: testAuthLoader);
    final presence = PresenceRepository(api: pbx.api, authLoader: testAuthLoader);
    await tester.pumpWidget(MaterialApp(home: ContactsTab(repository: dir, presence: presence)));
    await tester.runAsync(() async {
      await dir.init();
      await presence.refresh();
    });
    await tester.pumpAndSettle();

    expect(find.text('11 · telefoniert'), findsOneWidget);
    expect(find.text('15 · offline'), findsOneWidget);
    expect(find.text('16 · klingelt'), findsOneWidget);
    expect(find.text('17 · Mittagspause'), findsOneWidget);
    // Only the ringing colleague offers "Heranholen".
    expect(find.byKey(const Key('pickup-16')), findsOneWidget);
    expect(find.text('Heranholen'), findsOneWidget);
    // While it rings, the door station shows "Heranholen" instead of its door icon.
    expect(find.byIcon(Icons.door_front_door_outlined), findsNothing);

    Color? dotOf(String name) => tester
        .widget<ContactAvatar>(find.descendant(
          of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
          matching: find.byType(ContactAvatar),
        ))
        .dotColor;
    expect(dotOf('sandro'), AppColors.presenceBusy);
    expect(dotOf('Büro'), AppColors.presenceOffline);
    expect(dotOf('Lager'), AppColors.presenceLunch);
  });
}
