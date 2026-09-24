import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/screens/active_call_screen.dart';
import 'package:ha_phone_test/services/call_events.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/recordings_repository.dart';
import 'package:ha_phone_test/widgets/round_action_button.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
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
    // Wall clock: the timer may already show the next second.
    expect(find.textContaining(RegExp(r'^02:3[78]$')), findsOneWidget);
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

  group('recording', () {
    late FakePbx pbx;

    /// Call screen with a directory that does/doesn't allow recording.
    Future<void> pumpRecording(
      WidgetTester tester, {
      required bool allowed,
      Map<String, Object?>? call,
      http.Response Function(http.Request)? onRecording,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final shown = call ?? _call();
      sip = FakeSip({
        'getCurrentCall': (_) => shown,
        'getAudioRoutes': (_) => _routes('earpiece', ['earpiece', 'speaker']),
      })
        ..install();
      pbx = FakePbx({
        'GET /api/mobile/directory': (_) => jsonResponse({
              'self': {'number': '12', 'name': 'App', 'recording_allowed': allowed},
              'extensions': [],
            }),
        'POST /api/mobile/recording': onRecording ??
            (req) => jsonDecode(req.body)['action'] == 'start'
                ? jsonResponse({'recording': true, 'id': '20260924-101500_16'})
                : jsonResponse({'recording': false}),
      });
      final dir = DirectoryRepository(api: pbx.api, authLoader: testAuthLoader);
      await tester.runAsync(dir.refresh);
      final recordings = RecordingsRepository(api: pbx.api, authLoader: testAuthLoader);
      await tester.pumpWidget(MaterialApp(home: ActiveCallScreen(directory: dir, recordings: recordings)));
      await tester.pump();
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump();
    }

    RoundActionButton recordButton(WidgetTester tester) =>
        tester.widget<RoundActionButton>(find.byKey(const Key('record')));

    testWidgets('no Aufnehmen button unless the admin allows recording', (tester) async {
      await pumpRecording(tester, allowed: false);
      expect(find.text('Aufnehmen'), findsNothing);
      expect(find.text('Hinzufügen'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('Aufnehmen starts: red indicator with timer, Stopp ends it', (tester) async {
      await pumpRecording(tester, allowed: true);
      expect(find.text('Aufnehmen'), findsOneWidget);
      expect(find.byKey(const Key('recording-indicator')), findsNothing);

      await tester.tap(find.text('Aufnehmen'));
      await settle(tester);
      expect(jsonDecode(pbx.to('POST', '/api/mobile/recording').single.body), {'action': 'start', 'peer': '16'});
      expect(find.byKey(const Key('recording-indicator')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Aufnahme 00:0\d$')), findsOneWidget);
      expect(find.text('Stopp'), findsOneWidget);
      expect(recordButton(tester).active, isTrue);

      await tester.tap(find.text('Stopp'));
      await settle(tester);
      expect(jsonDecode(pbx.to('POST', '/api/mobile/recording').last.body), {'action': 'stop', 'peer': '16'});
      expect(find.byKey(const Key('recording-indicator')), findsNothing);
      expect(find.text('Aufnehmen'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('403 from the PBX shows a German SnackBar, no indicator', (tester) async {
      await pumpRecording(tester, allowed: true, onRecording: (_) => http.Response('{}', 403));
      await tester.tap(find.text('Aufnehmen'));
      await settle(tester);
      expect(find.text('Gesprächsaufzeichnung ist für Ihre Nebenstelle nicht freigegeben.'), findsOneWidget);
      expect(find.byKey(const Key('recording-indicator')), findsNothing);
      await dispose(tester);
    });

    testWidgets('409 on start explains that no unique call was found', (tester) async {
      await pumpRecording(tester, allowed: true, onRecording: (_) => http.Response('{}', 409));
      await tester.tap(find.text('Aufnehmen'));
      await settle(tester);
      expect(find.text('Aufnahme nicht gestartet – Gespräch auf der Anlage nicht eindeutig gefunden.'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('disabled until the call is answered', (tester) async {
      await pumpRecording(tester, allowed: true, call: _call(state: 'ringing', connectedAgoSec: -1));
      expect(recordButton(tester).onPressed, isNull);
      await dispose(tester);
    });

    testWidgets('indicator follows the line on screen when swapping lines', (tester) async {
      final lineA = _call();
      final lineB = {..._call(connectedAgoSec: 30), 'number': '13', 'name': 'Test'};
      await pumpRecording(tester, allowed: true, call: {...lineA, 'other': {...lineB, 'onHold': true}});
      await tester.tap(find.text('Aufnehmen'));
      await settle(tester);
      expect(find.byKey(const Key('recording-indicator')), findsOneWidget);

      // Makeln: 13 comes to the front, 16 (still recorded on the PBX) is held.
      sip.responses['getCurrentCall'] = (_) => {...lineB, 'other': {...lineA, 'onHold': true}};
      sip.emit({'type': 'callState', 'callId': '1', 'direction': 'incoming', 'state': 'confirmed'});
      await settle(tester);
      expect(find.byKey(const Key('recording-indicator')), findsNothing);
      expect(find.text('Aufnehmen'), findsOneWidget);

      sip.responses['getCurrentCall'] = (_) => {...lineA, 'other': {...lineB, 'onHold': true}};
      sip.emit({'type': 'callState', 'callId': '1', 'direction': 'incoming', 'state': 'confirmed'});
      await settle(tester);
      expect(find.byKey(const Key('recording-indicator')), findsOneWidget);
      expect(find.text('Stopp'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('seven buttons fit on a small 320 dp screen', (tester) async {
      tester.view.physicalSize = const Size(960, 1704);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await pumpRecording(tester, allowed: true);
      for (final label in ['Stumm', 'Tastatur', 'Hörer', 'Halten', 'Weiterleiten', 'Hinzufügen', 'Aufnehmen']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(tester.takeException(), isNull);
      await dispose(tester);
    });
  });
}
