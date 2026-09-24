import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/presence.dart';
import 'package:ha_phone_test/screens/start_tab.dart';
import 'package:ha_phone_test/services/app_navigation.dart';
import 'package:ha_phone_test/services/call_history_store.dart';
import 'package:ha_phone_test/services/call_launcher.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/door_opener.dart';
import 'package:ha_phone_test/services/favorites_store.dart';
import 'package:ha_phone_test/services/phone_contacts_repository.dart';
import 'package:ha_phone_test/services/presence_repository.dart';
import 'package:ha_phone_test/services/registration_watcher.dart';
import 'package:ha_phone_test/services/ring_settings_repository.dart';
import 'package:ha_phone_test/models/ring_settings.dart';
import 'package:ha_phone_test/services/voicemail_repository.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/utils/registration_ui.dart';
import 'package:ha_phone_test/utils/timeline.dart';
import 'package:ha_phone_test/widgets/presence_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_phone_contacts.dart';
import '../helpers/fake_sip.dart';

int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

class _Start {
  _Start(this.nav, this.actions);
  final AppNavigation nav;
  final List<(String, int)> actions;
}

void main() {
  late FakeSip sip;
  final now = DateTime.now();

  setUp(() {
    SharedPreferences.setMockInitialValues({'favorites_v1': ['11', '0171555']});
    CallLauncher.requestMicrophone = () async => true;
    sip = FakeSip({
      'getRegistrationState': (_) => 'registered',
      'getCallHistory': (_) => [
            historyEntry(id: 'd', number: '16', answered: false, startedAt: DateTime(now.year, now.month, now.day, 0, 7)),
          ],
    })
      ..install();
  });
  tearDown(() => sip.uninstall());

  FakePbx pbx({String ownLine = 'idle', bool voicemail = true, bool doorRemote = false, int doorOpenStatus = 200}) => FakePbx({
        'GET /api/mobile/directory': (_) => jsonResponse({
              'self': {'number': '18', 'name': 'Emulator-Test', 'presence': 'available'},
              'extensions': [
                {'number': '18', 'name': 'Emulator-Test'},
                {'number': '11', 'name': 'sandro'},
                {
                  'number': '16',
                  'name': 'Haustür',
                  'door_open_code': '*1',
                  'door_open_remote': doorRemote,
                  'video': true,
                  'door_actions': [
                    {'index': 0, 'label': 'Licht'},
                  ],
                },
              ],
              'phonebook': [
                {'number': '0171555', 'name': 'Oma Erika'},
              ],
            }),
        'POST /api/mobile/door-open': (_) => jsonResponse({'success': true}, doorOpenStatus),
        'GET /api/mobile/presence': (_) => jsonResponse({
              'self': {'number': '18', 'presence': 'available', 'line': ownLine},
              'extensions': [
                {'number': '11', 'presence': 'available', 'line': 'busy'},
              ],
            }),
        if (voicemail)
          'GET /api/mobile/voicemail': (_) => jsonResponse({
                'messages': [
                  {
                    'id': 'INBOX/msg0000',
                    'new': true,
                    'caller_number': '16',
                    'caller_name': 'Tür-Simulator',
                    'duration_sec': 12,
                    'received_at': _epoch(now.subtract(const Duration(minutes: 3))),
                  },
                ],
              }),
      });

  Future<_Start> pump(WidgetTester tester, FakePbx fake, {double textScale = 1, RingSettingsRepository? ring}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = DirectoryRepository(api: fake.api, authLoader: testAuthLoader);
    final presence = PresenceRepository(api: fake.api, authLoader: testAuthLoader, pollInterval: const Duration(hours: 1));
    final vm = VoicemailRepository(api: fake.api, authLoader: testAuthLoader);
    final history = CallHistoryStore(api: fake.api, authLoader: testAuthLoader);
    final reg = RegistrationWatcher();
    final nav = AppNavigation();
    final actions = <(String, int)>[];
    await tester.runAsync(() async {
      await FavoritesStore.instance.load();
      await dir.refresh();
      await presence.refresh();
      await vm.refresh();
      await history.load();
      await reg.start();
    });
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      routes: {'/active-call': (_) => const Scaffold(body: Text('ACTIVE'))},
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: const Size(390, 844)),
        child: StartTab(
          directory: dir,
          presence: presence,
          voicemail: vm,
          history: history,
          registration: reg,
          navigation: nav,
          ring: ring,
          phoneContacts: PhoneContactsRepository(source: FakePhoneContactsSource()),
          doorActionRunner: (n, i) async => actions.add((n, i)),
          doorOpener: DoorOpener(api: fake.api, authLoader: testAuthLoader),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return _Start(nav, actions);
  }

  test('pill text follows registration and presence', () {
    expect(startPillText(RegistrationUi.online, Presence.available), 'Klingelt hier · verfügbar');
    expect(startPillText(RegistrationUi.online, Presence.unknown), 'Klingelt hier');
    expect(startPillText(RegistrationUi.online, Presence.away, ring: 'Stumm bis 17:00'), 'Stumm bis 17:00 · abwesend');
    expect(startPillText(RegistrationUi.offline, Presence.available), 'Nicht verbunden');
  });

  testWidgets('header: own name, status pill opens the status sheet; search goes to Kontakte', (tester) async {
    final s = await pump(tester, pbx());

    expect(find.text('Emulator-Test · 18'), findsOneWidget);
    expect(find.text('Klingelt hier · verfügbar'), findsOneWidget);
    await tester.tap(find.byKey(const Key('start-status')));
    await tester.pumpAndSettle();
    expect(find.text('STATUS FÜR ALLE'), findsOneWidget);
    expect(find.text('Klingeln auf diesem Handy'), findsOneWidget);
    Navigator.of(tester.element(find.text('STATUS FÜR ALLE'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Kontakte suchen'));
    expect(s.nav.tab, AppTab.contacts);
    expect(s.nav.contactSearchRequests, 1);
  });

  testWidgets('pill: "Stumm bis 17:00 · verfügbar" with bell-off while this handset is muted', (tester) async {
    final ring = RingSettingsRepository(clock: () => DateTime(2026, 9, 24, 10));
    await tester.runAsync(() => ring.update(RingSettings(mutedUntil: DateTime(2026, 9, 24, 17))));
    await pump(tester, pbx(), ring: ring);
    expect(find.text('Stumm bis 17:00 · verfügbar'), findsOneWidget);
    expect(find.byKey(const Key('start-pill-bell-off')), findsOneWidget);

    await tester.runAsync(() => ring.update(ring.settings.ringing()));
    await tester.pumpAndSettle();
    expect(find.text('Klingelt hier · verfügbar'), findsOneWidget);
    expect(find.byKey(const Key('start-pill-bell')), findsOneWidget);
    ring.dispose();
  });

  testWidgets('door card: last ring, "Tür anrufen" calls the door, HA action runs without a call', (tester) async {
    final s = await pump(tester, pbx());

    expect(find.byKey(const ValueKey('door-card-16')), findsOneWidget);
    expect(find.text('zuletzt 00:07'), findsOneWidget);

    await tester.tap(find.byTooltip('Licht'));
    await tester.pump();
    expect(s.actions, [('16', 0)]);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('„Licht“ ausgeführt'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('door-call-16')));
    await tester.pumpAndSettle();
    expect(sip.callsTo('makeCall').single.arguments, '16');
  });

  testWidgets('door card with webhook: "Tür öffnen" opens without a call, green for 2 s', (tester) async {
    final fake = pbx(doorRemote: true);
    await pump(tester, fake);

    expect(find.byKey(const ValueKey('door-call-16')), findsNothing);
    expect(find.text('Tür öffnen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('door-open-16')));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
    expect(jsonDecode(fake.to('POST', '/api/mobile/door-open').single.body), {'extension': '16'});
    expect(find.text('Tür geöffnet ✓'), findsOneWidget);
    expect(sip.callsTo('makeCall'), isEmpty);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Tür öffnen'), findsOneWidget);
  });

  testWidgets('door card with webhook: 404 offers calling the door instead', (tester) async {
    final fake = pbx(doorRemote: true, doorOpenStatus: 404);
    await pump(tester, fake);

    await tester.tap(find.byKey(const ValueKey('door-open-16')));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
    expect(find.text('Für diese Tür ist kein Öffnen ohne Anruf eingerichtet.'), findsOneWidget);
    expect(find.text('Tür geöffnet ✓'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(SnackBarAction, 'Anrufen'));
    await tester.pumpAndSettle();
    expect(sip.callsTo('makeCall').single.arguments, '16');
  });

  testWidgets('favourites: 2-column tiles with live presence; tap calls', (tester) async {
    await pump(tester, pbx());

    expect(find.byKey(const ValueKey('fav-11')), findsOneWidget);
    expect(find.byKey(const ValueKey('fav-0171555')), findsOneWidget);
    final avatar = tester.widget<PresenceAvatar>(
      find.descendant(of: find.byKey(const ValueKey('fav-11')), matching: find.byType(PresenceAvatar)),
    );
    expect(avatar.presence, AvatarPresence.busy);
    expect(find.text('telefoniert'), findsOneWidget);
    // Two tiles side by side.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('fav-11'))).dy,
      tester.getTopLeft(find.byKey(const ValueKey('fav-0171555'))).dy,
    );

    await tester.tap(find.byKey(const ValueKey('fav-11')));
    await tester.pumpAndSettle();
    expect(sip.callsTo('makeCall').single.arguments, '11');
  });

  testWidgets('new voicemail card opens Verlauf with the Voicemail filter', (tester) async {
    final s = await pump(tester, pbx());
    await tester.scrollUntilVisible(find.byKey(const Key('start-voicemail')), 200);
    expect(find.text('Neue Voicemail · Tür-Simulator'), findsOneWidget);

    await tester.tap(find.byKey(const Key('start-voicemail')));
    expect(s.nav.tab, AppTab.history);
    expect(s.nav.takeHistoryFilter(), TimelineFilter.voicemail);
  });

  testWidgets('call on another device: flip card dials *55', (tester) async {
    await pump(tester, pbx(ownLine: 'busy'));
    expect(find.byKey(const Key('call-flip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('call-flip-take')));
    await tester.pumpAndSettle();
    expect(sip.callsTo('makeCall').single.arguments, '*55');
  });

  testWidgets('no voicemail card and no flip card when there is nothing to show', (tester) async {
    await pump(tester, pbx(voicemail: false));
    expect(find.byKey(const Key('start-voicemail')), findsNothing);
    expect(find.byKey(const Key('call-flip')), findsNothing);
  });

  testWidgets('no overflow at 200 % text size', (tester) async {
    await pump(tester, pbx(ownLine: 'busy'), textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.byKey(const Key('start-voicemail')), 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
