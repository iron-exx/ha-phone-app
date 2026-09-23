import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/call_launcher.dart';
import 'package:ha_phone_test/widgets/dialer_view.dart';

import '../helpers/fake_sip.dart';

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
}
