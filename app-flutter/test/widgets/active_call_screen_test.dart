import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/screens/active_call_screen.dart';
import 'package:ha_phone_test/services/call_events.dart';
import 'package:ha_phone_test/widgets/round_action_button.dart';

import '../helpers/fake_sip.dart';

Map<String, Object?> _call({String doorCode = '', String state = 'confirmed', int connectedAgoSec = 157}) => {
      'number': '16',
      'name': 'türklingel',
      'direction': 'incoming',
      'video': false,
      'doorCode': doorCode,
      'state': state,
      'connectedAtMs': connectedAgoSec < 0
          ? 0
          : DateTime.now().subtract(Duration(seconds: connectedAgoSec)).millisecondsSinceEpoch,
      'secure': true,
    };

Map<String, Object?> _routes(String current, List<String> types) => {
      'current': current,
      'routes': [
        for (final t in types) {'id': t, 'name': t, 'type': t},
      ],
    };

void main() {
  late FakeSip sip;

  setUp(() => CallEvents.instance.lastDisconnected = null);
  tearDown(() => sip.uninstall());

  Future<void> pumpCall(WidgetTester tester, Map<String, Object?> call, Map<String, Object?> routes) async {
    sip = FakeSip({
      'getCurrentCall': (_) => call,
      'getAudioRoutes': (_) => routes,
    })
      ..install();
    await tester.pumpWidget(const MaterialApp(home: ActiveCallScreen()));
    await tester.pump();
    await tester.pump();
  }

  /// The screen runs a 1 s ticker; replace it so the timer is cancelled.
  Future<void> dispose(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  testWidgets('door call shows duration, TLS and sends the door code', (tester) async {
    await pumpCall(tester, _call(doorCode: '*1'), _routes('earpiece', ['earpiece', 'speaker']));

    expect(find.text('türklingel'), findsOneWidget);
    expect(find.text('16 · Türstation'), findsOneWidget);
    expect(find.text('02:37'), findsOneWidget);
    expect(find.text('TLS'), findsOneWidget);
    expect(find.text('Konferenz'), findsNothing);

    await tester.tap(find.text('Tür öffnen'));
    await tester.pump();
    expect(sip.callsTo('openDoor'), hasLength(1));
    expect(find.text('Tür-Code gesendet'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('non-door call offers Hinzufügen for a second call', (tester) async {
    await pumpCall(tester, _call(state: 'ringing', connectedAgoSec: -1), _routes('earpiece', ['earpiece', 'speaker']));

    expect(find.text('Klingelt…'), findsOneWidget);
    expect(find.text('Tür öffnen'), findsNothing);
    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('Anruf hinzufügen'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('call waiting card answers or rejects the knocking call', (tester) async {
    final call = {..._call(), 'other': {..._call(), 'number': '13', 'name': 'Test', 'state': 'waiting'}};
    await pumpCall(tester, call, _routes('earpiece', ['earpiece', 'speaker']));

    expect(find.text('Anklopfen: Test'), findsOneWidget);
    await tester.tap(find.byKey(const Key('answer-waiting')));
    await tester.pump();
    expect(sip.callsTo('answerWaiting'), hasLength(1));
    await tester.tap(find.byKey(const Key('reject-waiting')));
    await tester.pump();
    expect(sip.callsTo('rejectWaiting'), hasLength(1));
    // A second line is up, so no third one can be added.
    expect(tester.widget<RoundActionButton>(find.widgetWithText(RoundActionButton, 'Hinzufügen')).onPressed, isNull);
    await dispose(tester);
  });

  testWidgets('held call card swaps, connects and merges', (tester) async {
    final call = {..._call(), 'other': {..._call(), 'number': '13', 'name': 'Test', 'onHold': true}};
    await pumpCall(tester, call, _routes('earpiece', ['earpiece', 'speaker']));

    expect(find.text('Gehalten: Test'), findsOneWidget);
    for (final entry in {'swap': 'swapCalls', 'connect': 'transferAttended', 'merge': 'mergeCalls'}.entries) {
      await tester.tap(find.byKey(Key(entry.key)));
      await tester.pump();
      expect(sip.callsTo(entry.value), hasLength(1), reason: entry.value);
    }
    await dispose(tester);
  });

  testWidgets('door call shows Home Assistant actions and runs them by index', (tester) async {
    final call = {..._call(doorCode: '*1'), 'doorActions': ['Licht', 'Garage']};
    await pumpCall(tester, call, _routes('earpiece', ['earpiece', 'speaker']));

    await tester.tap(find.byKey(const Key('door-action-1')));
    await tester.pump();
    expect(sip.callsTo('runDoorAction').single.arguments, {'number': '16', 'index': 1});
    expect(find.text('Garage: erledigt'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('conference card shows the partner without line actions', (tester) async {
    final call = {..._call(), 'conference': true, 'other': {..._call(), 'number': '13', 'name': 'Test'}};
    await pumpCall(tester, call, _routes('earpiece', ['earpiece', 'speaker']));

    expect(find.text('Konferenz mit Test'), findsOneWidget);
    expect(find.byKey(const Key('swap')), findsNothing);
    await dispose(tester);
  });

  testWidgets('speaker button toggles directly without Bluetooth', (tester) async {
    await pumpCall(tester, _call(), _routes('earpiece', ['earpiece', 'speaker']));

    expect(find.text('Hörer'), findsOneWidget);
    await tester.tap(find.text('Hörer'));
    await tester.pump();
    expect(sip.callsTo('setAudioRoute').single.arguments, 'speaker');

    sip.emit({'type': 'audioRoute', ..._routes('speaker', ['earpiece', 'speaker'])});
    await tester.pump();
    expect(find.text('Lautsprecher'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('with Bluetooth the speaker button opens a route picker', (tester) async {
    await pumpCall(tester, _call(), _routes('bluetooth', ['earpiece', 'speaker', 'bluetooth']));

    await tester.tap(find.text('Bluetooth'));
    await tester.pumpAndSettle();
    expect(find.text('Audio-Ausgabe'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('speaker'));
    await tester.pumpAndSettle();
    expect(sip.callsTo('setAudioRoute').single.arguments, 'speaker');
    await dispose(tester);
  });

  testWidgets('hang-up calls native hangup and leaves', (tester) async {
    await pumpCall(tester, _call(), _routes('earpiece', ['earpiece', 'speaker']));
    await tester.tap(find.byKey(const Key('hangup')));
    await tester.pump();
    expect(sip.callsTo('hangup'), hasLength(1));
    await dispose(tester);
  });
}
