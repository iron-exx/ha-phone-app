import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/screens/app_shell.dart';
import 'package:ha_phone_test/services/app_navigation.dart';
import 'package:ha_phone_test/services/call_history_store.dart';
import 'package:ha_phone_test/services/presence_repository.dart';
import 'package:ha_phone_test/services/voicemail_repository.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_sip.dart';

int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

void main() {
  late FakeSip sip;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    sip = FakeSip({
      'getCallHistory': (_) => [
            historyEntry(id: '1', number: '16', name: 'türklingel', answered: false, video: true, startedAt: now),
            historyEntry(id: '2', number: '0174123', answered: false, startedAt: now.subtract(const Duration(minutes: 5))),
            historyEntry(id: '3', number: '12', direction: 'outgoing', durationSec: 41, startedAt: now),
          ],
      'getRegistrationState': (_) => 'registered',
      'getDeviceAuth': (_) => <String, String>{},
    })
      ..install();
  });

  tearDown(() => sip.uninstall());

  Future<({AppNavigation nav, VoicemailRepository vm})> pumpShell(WidgetTester tester) async {
    final fake = FakePbx({
      'GET /api/mobile/voicemail': (_) => jsonResponse({
            'messages': [
              {
                'id': 'INBOX/msg0000',
                'new': true,
                'caller_number': '0171555',
                'caller_name': 'Oma Erika',
                'duration_sec': 12,
                'received_at': _epoch(DateTime.now().subtract(const Duration(minutes: 1))),
              },
            ],
          }),
    });
    final nav = AppNavigation();
    final vm = VoicemailRepository(api: fake.api, authLoader: testAuthLoader, pollInterval: const Duration(hours: 1));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: AppShell(
        onSetupChanged: () async {},
        onUnpaired: () async {},
        navigation: nav,
        history: CallHistoryStore(api: fake.api, authLoader: testAuthLoader),
        voicemail: vm,
        presence: PresenceRepository(api: fake.api, authLoader: testAuthLoader, pollInterval: const Duration(hours: 1)),
      ),
    ));
    await tester.runAsync(vm.refresh);
    await tester.pumpAndSettle();
    return (nav: nav, vm: vm);
  }

  Finder badge(String text) =>
      find.descendant(of: find.byKey(const ValueKey('badge-history')), matching: find.text(text));

  testWidgets('bottom bar: Start · Verlauf · Wählen · Kontakte · Ich, Start first', (tester) async {
    await pumpShell(tester);

    for (final tab in AppTab.values) {
      expect(find.byKey(ValueKey('tab-${tab.name}')), findsOneWidget);
    }
    for (final label in ['Start', 'Verlauf', 'Kontakte', 'Ich']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.bySemanticsLabel('Wählen'), findsOneWidget);
    expect(find.text('Voicemail'), findsNothing, reason: 'no separate Voicemail tab any more');
    expect(find.byKey(const Key('start-pill')), findsOneWidget);
    expect(find.text('Klingelt hier'), findsOneWidget);
  });

  testWidgets('Verlauf badge counts missed calls plus new voicemails; opening clears the missed part',
      (tester) async {
    await pumpShell(tester);
    expect(badge('3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab-history')));
    await tester.pumpAndSettle();

    expect(badge('1'), findsOneWidget, reason: 'the voicemail is still unheard');
    expect(find.text('verpasst · Video'), findsOneWidget);
    expect(find.text('ausgehend · 0:41'), findsOneWidget);
    // Name falls back to the number when neither the entry nor the directory knows it.
    expect(find.text('0174123'), findsOneWidget);
  });

  testWidgets('Start "Neue Voicemail" opens Verlauf with the Voicemail filter', (tester) async {
    final h = await pumpShell(tester);
    expect(find.text('Neue Voicemail · Oma Erika'), findsOneWidget);

    await tester.tap(find.byKey(const Key('start-voicemail')));
    await tester.pumpAndSettle();

    expect(h.nav.tab, AppTab.history);
    expect(find.text('Voicemail · 0:12'), findsOneWidget);
    expect(find.text('türklingel'), findsNothing, reason: 'filter is Voicemail');
  });

  testWidgets('the raised centre button opens the dialer', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('tab-dial')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dialer-display')), findsOneWidget);
    expect(find.text('bereit'), findsOneWidget);
  });

  testWidgets('swipe in Verlauf deletes a history entry natively', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('tab-history')));
    await tester.pumpAndSettle();

    await tester.drag(find.text('türklingel'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(sip.callsTo('deleteCallHistoryEntry').single.arguments, '1');
    expect(find.text('türklingel'), findsNothing);
  });

  testWidgets('Ich tab shows the live registration state', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('tab-me')));
    await tester.pumpAndSettle();
    // The connection row sits in "Gerät", below the status panel.
    await tester.scrollUntilVisible(find.text('Online (TLS)'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Online (TLS)'), findsOneWidget);

    sip.emit({'type': 'registrationState', 'state': 'failed'});
    await tester.pumpAndSettle();
    expect(find.text('Nicht verbunden'), findsWidgets);
  });
}
