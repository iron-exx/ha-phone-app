import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/screens/contacts_tab.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/phone_contacts_repository.dart';
import 'package:ha_phone_test/services/phone_contacts_source.dart';
import 'package:ha_phone_test/services/presence_repository.dart';
import 'package:ha_phone_test/services/app_navigation.dart';
import 'package:ha_phone_test/services/call_launcher.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/widgets/presence_avatar.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_phone_contacts.dart';
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
    CallLauncher.requestMicrophone = () async => true;
    sip = FakeSip()..install();
  });
  tearDown(() => sip.uninstall());

  DirectoryRepository repo(http.Response response) => DirectoryRepository(
        api: ApiClient(client: MockClient((_) async => response)),
        authLoader: () async => const DeviceAuth(apiHost: 'box', deviceId: '1', deviceToken: 't'),
      );

  Future<void> pumpTab(
    WidgetTester tester,
    DirectoryRepository r, {
    PhoneContactsRepository? phone,
    AppNavigation? navigation,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      routes: {'/active-call': (_) => const Scaffold(body: Text('ACTIVE'))},
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: const Size(390, 844)),
        child: ContactsTab(
          repository: r,
          navigation: navigation ?? AppNavigation(),
          phoneContacts: phone ?? PhoneContactsRepository(source: FakePhoneContactsSource()),
        ),
      ),
    ));
    await tester.runAsync(r.init);
    await tester.pumpAndSettle();
  }

  testWidgets('sections: door stations, colleagues with presence, phonebook; without self', (tester) async {
    final r = repo(http.Response.bytes(utf8.encode(jsonEncode(_body)), 200));
    await pumpTab(tester, r);

    expect(find.text('TÜRSTATIONEN'), findsOneWidget);
    expect(find.text('KOLLEG:INNEN'), findsOneWidget);
    expect(find.text('TELEFONBUCH'), findsOneWidget);
    expect(find.text('Mittagspause · 11'), findsOneWidget);
    expect(find.text('Türstation · 16 · Video'), findsOneWidget);
    expect(find.byKey(const ValueKey('door-call-16')), findsOneWidget);
    expect(find.text('Test'), findsNothing);
    expect(sip.callsTo('setDoorCodes').single.arguments, {'16': '*1'});
  });

  testWidgets('call button dials, row tap opens the details sheet', (tester) async {
    final r = repo(http.Response.bytes(utf8.encode(jsonEncode(_body)), 200));
    await pumpTab(tester, r);

    await tester.tap(find.byTooltip('sandro anrufen'));
    await tester.pumpAndSettle();
    expect(sip.callsTo('makeCall').single.arguments, '11');
    Navigator.of(tester.element(find.text('ACTIVE'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('sandro'));
    await tester.pumpAndSettle();
    expect(find.text('Nebenstelle 11 · Mittagspause'), findsOneWidget);
    expect(find.text('Favorit'), findsOneWidget);
  });

  testWidgets('door station row calls the door', (tester) async {
    final r = repo(http.Response.bytes(utf8.encode(jsonEncode(_body)), 200));
    await pumpTab(tester, r);
    await tester.tap(find.byKey(const ValueKey('door-call-16')));
    await tester.pumpAndSettle();
    expect(sip.callsTo('makeCall').single.arguments, '16');
  });

  testWidgets('navigation: search request focuses the field, favourites request selects the chip', (tester) async {
    final r = repo(http.Response.bytes(utf8.encode(jsonEncode(_body)), 200));
    final nav = AppNavigation();
    await pumpTab(tester, r, navigation: nav);

    nav.openContactSearch();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus, isTrue);

    nav.openFavorites();
    await tester.pumpAndSettle();
    expect(find.textContaining('Noch keine Favoriten'), findsOneWidget);
  });

  testWidgets('no overflow at 200 % text size', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final r = repo(http.Response.bytes(utf8.encode(jsonEncode(_body)), 200));
    await pumpTab(tester, r, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('sandro'), findsOneWidget);
  });

  testWidgets('search and phonebook segment', (tester) async {
    final r = repo(http.Response.bytes(utf8.encode(jsonEncode(_body)), 200));
    await pumpTab(tester, r);

    await tester.enterText(find.byType(TextField), 'sand');
    await tester.pump();
    expect(find.text('sandro'), findsOneWidget);
    expect(find.text('türklingel'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byKey(const ValueKey('segment-phonebook')));
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
              {'number': '18', 'name': 'Küche', 'presence': 'available'},
            ],
          }),
      'GET /api/mobile/presence': (_) => jsonResponse({
            'self': {'number': '13', 'presence': 'available', 'line': 'idle'},
            'extensions': [
              {'number': '11', 'presence': 'lunch', 'line': 'busy'},
              {'number': '15', 'presence': 'available', 'line': 'offline'},
              {'number': '16', 'presence': 'available', 'line': 'idle'},
              {'number': '17', 'presence': 'available', 'line': 'ringing'},
              {'number': '18', 'presence': 'lunch', 'line': 'idle'},
            ],
          }),
    });
    final dir = DirectoryRepository(api: pbx.api, authLoader: testAuthLoader);
    final presence = PresenceRepository(api: pbx.api, authLoader: testAuthLoader);
    await tester.pumpWidget(MaterialApp(
      home: ContactsTab(
        repository: dir,
        presence: presence,
        navigation: AppNavigation(),
        phoneContacts: PhoneContactsRepository(source: FakePhoneContactsSource()),
      ),
    ));
    await tester.runAsync(() async {
      await dir.init();
      await presence.refresh();
    });
    await tester.pumpAndSettle();

    expect(find.text('telefoniert · 11'), findsOneWidget);
    expect(find.text('offline · 15'), findsOneWidget);
    expect(find.text('klingelt · 17'), findsOneWidget);
    expect(find.text('Mittagspause · 18'), findsOneWidget);
    // Only the ringing colleague offers "Heranholen" (instead of the call button).
    expect(find.byKey(const Key('pickup-17')), findsOneWidget);
    expect(find.text('Heranholen'), findsOneWidget);
    expect(find.byTooltip('Lager anrufen'), findsNothing);

    AvatarPresence? presenceOf(String name) => tester
        .widget<PresenceAvatar>(find.descendant(
          of: find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first,
          matching: find.byType(PresenceAvatar),
        ))
        .presence;
    expect(presenceOf('sandro'), AvatarPresence.busy);
    expect(presenceOf('Büro'), AvatarPresence.offline);
    expect(presenceOf('Lager'), AvatarPresence.busy);
    expect(presenceOf('Küche'), AvatarPresence.away);
  });

  group('Handy source', () {
    Future<(PhoneContactsRepository, FakePhoneContactsSource)> pumpPhone(
      WidgetTester tester,
      FakePhoneContactsSource src,
    ) async {
      final phone = PhoneContactsRepository(source: src);
      await pumpTab(tester, repo(http.Response.bytes(utf8.encode(jsonEncode(_body)), 200)), phone: phone);
      await tester.ensureVisible(find.byKey(const ValueKey('segment-phone')));
      await tester.tap(find.byKey(const ValueKey('segment-phone')));
      await tester.runAsync(phone.ensureLoaded);
      await tester.pumpAndSettle();
      return (phone, src);
    }

    testWidgets('first visit explains and asks, granting lists one row per number', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (phone, src) = await pumpPhone(
        tester,
        FakePhoneContactsSource(contacts: [
          phoneContact('Mama', '+49 171 5550', 'Mobil'),
          phoneContact('Mama', '030 998877', 'Privat'),
        ]),
      );

      expect(find.byKey(const Key('phone-contacts-explain')), findsOneWidget);
      expect(find.text('Zugriff erlauben'), findsOneWidget);
      expect(src.loadCount, 0);
      expect(tester.takeException(), isNull); // no overflow at 360 dp

      await tester.tap(find.text('Zugriff erlauben'));
      await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(src.requestCount, 1);
      expect(phone.access, PhoneContactsAccess.granted);
      expect(find.text('Mobil · +49 171 5550'), findsOneWidget);
      expect(find.text('Privat · 030 998877'), findsOneWidget);
      expect(find.text('Mama'), findsNWidgets(2));
    });

    testWidgets('denied shows the settings hint', (tester) async {
      final (_, src) = await pumpPhone(tester, FakePhoneContactsSource(access: PhoneContactsAccess.denied));
      expect(find.byKey(const Key('phone-contacts-denied')), findsOneWidget);
      await tester.tap(find.text('Einstellungen öffnen'));
      await tester.pump();
      expect(src.settingsOpened, 1);
    });

    testWidgets('search covers all sources with section headers', (tester) async {
      final phone = PhoneContactsRepository(
        source: FakePhoneContactsSource(
          access: PhoneContactsAccess.granted,
          contacts: [phoneContact('Pizza Handy', '0171 1')],
        ),
      );
      await pumpTab(tester, repo(http.Response.bytes(utf8.encode(jsonEncode(_body)), 200)), phone: phone);
      await tester.enterText(find.byType(TextField), 'pizz');
      await tester.runAsync(phone.ensureLoaded);
      await tester.pumpAndSettle();

      expect(find.text('TELEFONBUCH · 1'), findsOneWidget);
      expect(find.text('HANDY · 1'), findsOneWidget);
      expect(find.text('NEBENSTELLEN · 1'), findsNothing);
      expect(find.text('Pizzeria'), findsOneWidget);
      expect(find.text('Pizza Handy'), findsOneWidget);
    });
  });
}
