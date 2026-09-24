import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/contact.dart';
import 'package:ha_phone_test/services/call_launcher.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/presence_repository.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/widgets/dialer_view.dart';
import 'package:ha_phone_test/widgets/dialpad_grid.dart';
import 'package:ha_phone_test/widgets/presence_avatar.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_sip.dart';
import '../helpers/semantics.dart';

void main() {
  late FakeSip sip;

  setUp(() {
    sip = FakeSip()..install();
    CallLauncher.requestMicrophone = () async => true;
  });

  tearDown(() => sip.uninstall());

  Future<void> pumpDialer(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      routes: {
        '/': (_) => const Scaffold(body: DialerView()),
        '/active-call': (_) => const Scaffold(body: Text('ACTIVE')),
      },
    ));
  }

  FakePbx pbx() => FakePbx({
        'GET /api/mobile/directory': (_) => jsonResponse({
              'self': {'number': '18', 'name': 'Ich'},
              'extensions': [
                {'number': '18', 'name': 'Ich'},
                {'number': '11', 'name': 'sandro'},
                {'number': '113', 'name': 'Lager'},
              ],
              'phonebook': [
                {'number': '0301234567', 'name': 'Pizzeria'},
              ],
            }),
        'GET /api/mobile/presence': (_) => jsonResponse({
              'self': {'number': '18', 'line': 'idle'},
              'extensions': [
                {'number': '11', 'presence': 'available', 'line': 'busy'},
              ],
            }),
      });

  Future<void> pumpWithDirectory(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = pbx();
    final dir = DirectoryRepository(api: fake.api, authLoader: testAuthLoader);
    final presence = PresenceRepository(api: fake.api, authLoader: testAuthLoader);
    await tester.runAsync(() async {
      await dir.refresh();
      await presence.refresh();
    });
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      routes: {
        '/': (_) => MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: const Size(390, 844)),
              child: Scaffold(body: SafeArea(child: DialerView(directory: dir, presence: presence))),
            ),
        '/active-call': (_) => const Scaffold(body: Text('ACTIVE')),
      },
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String d) => find.descendant(of: find.byType(DialpadGrid), matching: find.text(d));

  String display(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('dialer-display'))).data!;

  testWidgets('types digits, backspaces and clears on long-press', (tester) async {
    await pumpDialer(tester);
    for (final d in ['1', '3', '*']) {
      await tester.tap(find.text(d));
    }
    await tester.pump();
    expect(display(tester), '13*');

    await tester.tap(find.byKey(const Key('dialer-backspace')));
    await tester.pump();
    expect(display(tester), '13');

    await tester.longPress(find.byKey(const Key('dialer-backspace')));
    await tester.pump();
    expect(display(tester), 'Nummer eingeben');
  });

  testWidgets('call button dials and opens the active-call screen', (tester) async {
    await pumpDialer(tester);
    await tester.tap(find.text('1'));
    await tester.tap(find.text('6'));
    await tester.pump();

    await tester.tap(find.byKey(const Key('dialer-call')));
    await tester.pumpAndSettle();

    expect(sip.callsTo('makeCall').single.arguments, '16');
    expect(find.text('ACTIVE'), findsOneWidget);
  });

  testWidgets('clears after dialing and redials the last number on an empty call tap', (tester) async {
    await pumpDialer(tester);
    await tester.tap(find.text('1'));
    await tester.tap(find.text('3'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('dialer-call')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('ACTIVE'))).pop();
    await tester.pumpAndSettle();
    expect(display(tester), 'Nummer eingeben');

    await tester.tap(find.byKey(const Key('dialer-call')));
    await tester.pump();
    expect(display(tester), '13');
    expect(sip.callsTo('makeCall'), hasLength(1));
  });

  testWidgets('does not dial without microphone permission', (tester) async {
    CallLauncher.requestMicrophone = () async => false;
    await pumpDialer(tester);
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('dialer-call')));
    await tester.pumpAndSettle();

    expect(sip.callsTo('makeCall'), isEmpty);
    expect(find.textContaining('Mikrofon-Berechtigung'), findsOneWidget);
  });

  testWidgets('live matches under the number, with presence; tap dials the match', (tester) async {
    await pumpWithDirectory(tester);
    await tester.tap(key('1'));
    await tester.tap(key('1'));
    await tester.pump();

    expect(find.text('sandro'), findsOneWidget);
    expect(find.text('Lager'), findsOneWidget);
    expect(find.text('Ich'), findsNothing, reason: 'own extension is no match');
    final avatar = tester.widget<PresenceAvatar>(
      find.descendant(of: find.byKey(const ValueKey('dialer-match-11')), matching: find.byType(PresenceAvatar)),
    );
    expect(avatar.presence, AvatarPresence.busy);

    await tester.tap(find.byKey(const ValueKey('dialer-match-113')));
    await tester.pumpAndSettle();
    expect(sip.callsTo('makeCall').single.arguments, '113');
  });

  testWidgets('phonebook numbers match on digits', (tester) async {
    await pumpWithDirectory(tester);
    for (final d in ['0', '3', '0']) {
      await tester.tap(key(d));
    }
    await tester.pump();
    expect(find.text('Pizzeria'), findsOneWidget);
  });

  testWidgets('no overflow at 200 % text size', (tester) async {
    await pumpWithDirectory(tester, textScale: 2);
    await tester.tap(key('1'));
    await tester.tap(key('1'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('dialer-call')), findsOneWidget);
  });

  testWidgets('TalkBack: dial keys are tappable via semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDialer(tester);
    for (final d in ['1', '3']) {
      semanticsAction(tester, key(d));
      await tester.pump();
    }
    expect(display(tester), '13');
    handle.dispose();
  });

  testWidgets('Wählen: touch targets ≥ 48 dp and labelled', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpWithDirectory(tester);
    await tester.tap(key('1'));
    await tester.tap(key('1'));
    await tester.pump();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('dialerMatches', () {
    test('needs two digits, dedupes by number, caps at three', () {
      const a = [
        Contact(number: '11', name: 'a'),
        Contact(number: '110', name: 'b'),
        Contact(number: '111', name: 'c'),
        Contact(number: '112', name: 'd'),
      ];
      const b = [Contact(number: '11', name: 'dupe', isExtension: false)];
      expect(dialerMatches('1', [a]), isEmpty);
      expect(dialerMatches('11', [b, a]).map((c) => c.name), ['dupe', 'b', 'c']);
    });
  });
}
