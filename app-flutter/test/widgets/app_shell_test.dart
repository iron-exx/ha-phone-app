import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/screens/app_shell.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_sip.dart';

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

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(onSetupChanged: () async {}, onUnpaired: () async {}),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows five tabs and a missed-call badge that clears on open', (tester) async {
    await pumpShell(tester);

    for (final label in ['Kontakte', 'Anrufe', 'Tastatur', 'Voicemail', 'Ich']) {
      expect(find.text(label), findsWidgets);
    }
    final badge = find.descendant(of: find.byType(Badge), matching: find.text('2'));
    expect(badge, findsOneWidget);

    await tester.tap(find.text('Anrufe').last);
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(Badge), matching: find.text('2')), findsNothing);
    expect(find.text('verpasst · Video'), findsOneWidget);
    expect(find.text('ausgehend · 0:41'), findsOneWidget);
    // Name falls back to the number when neither the entry nor the directory knows it.
    expect(find.text('0174123'), findsOneWidget);
  });

  testWidgets('Verpasst filter hides answered calls', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('Anrufe').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verpasst'));
    await tester.pumpAndSettle();

    expect(find.text('ausgehend · 0:41'), findsNothing);
    expect(find.text('verpasst'), findsOneWidget);
  });

  testWidgets('swipe deletes a history entry natively', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('Anrufe').last);
    await tester.pumpAndSettle();

    await tester.drag(find.text('türklingel'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(sip.callsTo('deleteCallHistoryEntry').single.arguments, '1');
    expect(find.text('türklingel'), findsNothing);
  });

  testWidgets('Ich tab shows the live registration state', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('Ich').last);
    await tester.pumpAndSettle();
    expect(find.text('Online (TLS)'), findsOneWidget);

    sip.emit({'type': 'registrationState', 'state': 'failed'});
    await tester.pumpAndSettle();
    expect(find.text('Nicht verbunden'), findsOneWidget);
  });
}
