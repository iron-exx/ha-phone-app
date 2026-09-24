import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/screens/active_call_screen.dart';
import 'package:ha_phone_test/services/call_events.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/door_opener.dart';
import 'package:ha_phone_test/services/recordings_repository.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/widgets/call_controls.dart';
import 'package:ha_phone_test/widgets/call_video_card.dart';
import 'package:ha_phone_test/widgets/transfer_sheet.dart';
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

Map<String, Object?> _person({int connectedAgoSec = 157}) =>
    {..._call(connectedAgoSec: connectedAgoSec), 'number': '0171555', 'name': 'Oma Erika'};

Map<String, Object?> _routes(String current, List<String> types, {Map<String, String> names = const {}}) => {
      'current': current,
      'routes': [
        for (final t in types) {'id': t, 'name': names[t] ?? t, 'type': t},
      ],
    };

final _earSpeaker = _routes('earpiece', ['earpiece', 'speaker']);

void main() {
  late FakeSip sip;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => sip.uninstall());

  /// Phone-sized surface (412×915 dp unless [size] is given).
  void phone(WidgetTester tester, [Size size = const Size(412, 915)]) {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  /// Directory with [extensions] (e.g. the door with `door_open_remote`).
  Future<DirectoryRepository> directory(WidgetTester tester, FakePbx pbx) async {
    final dir = DirectoryRepository(api: pbx.api, authLoader: testAuthLoader);
    await tester.runAsync(dir.refresh);
    return dir;
  }

  Future<void> pumpCall(
    WidgetTester tester,
    Map<String, Object?>? call, {
    Map<String, Object?>? routes,
    DirectoryRepository? dir,
    RecordingsRepository? recordings,
    DoorOpener? opener,
    Size size = const Size(412, 915),
    double textScale = 1,
    ThemeData? theme,
  }) async {
    phone(tester, size);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    sip = FakeSip({
      'getCurrentCall': (_) => call,
      'getAudioRoutes': (_) => routes ?? _earSpeaker,
    })
      ..install();
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: ActiveCallScreen(
        directory: dir ?? DirectoryRepository(api: FakePbx({}).api, authLoader: testAuthLoader),
        recordings: recordings ?? RecordingsRepository(api: FakePbx({}).api, authLoader: testAuthLoader),
        doorOpener: opener,
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  /// The screen runs a 1 s ticker; replace it so the timer is cancelled.
  Future<void> dispose(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
  }

  Future<void> openMore(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('more')));
    await tester.pumpAndSettle();
    expect(find.text('Mehr im Gespräch'), findsOneWidget);
  }

  CallControlButton control(WidgetTester tester, String key) => tester.widget<CallControlButton>(find.byKey(Key(key)));

  group('normal call', () {
    testWidgets('avatar, name, number · duration, TLS and the 2×3 grid; no tab bar', (tester) async {
      await pumpCall(tester, _person());

      expect(find.text('Oma Erika'), findsOneWidget);
      expect(find.text('0171555'), findsOneWidget);
      // Wall clock: the timer may already show the next second.
      expect(find.textContaining(RegExp(r'^02:3[78]$')), findsOneWidget);
      expect(find.text('TLS'), findsOneWidget);
      for (final label in ['Stumm', 'Lautsprecher', 'Halten', 'Tastatur', 'Weiterleiten', 'Mehr']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Tür öffnen'), findsNothing);
      expect(find.byKey(const Key('merge')), findsNothing, reason: 'Zusammenführen only with two lines');
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const Key('recording-indicator')), findsNothing);
      await dispose(tester);
    });

    testWidgets('Stumm and Halten toggle natively and invert the tile', (tester) async {
      await pumpCall(tester, _person());

      await tester.tap(find.text('Stumm'));
      await tester.pump();
      expect(sip.callsTo('mute').single.arguments, isTrue);
      expect(control(tester, 'mute').active, isTrue);
      expect(tester.getSemantics(find.byKey(const Key('mute'))), matchesSemantics(
        label: 'Stumm',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ));

      await tester.tap(find.text('Halten'));
      await tester.pump();
      expect(sip.callsTo('hold').single.arguments, isTrue);
      expect(find.text('Fortsetzen'), findsOneWidget);
      expect(find.textContaining('gehalten'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('ringing: Mehr → Rückfrage opens "Anruf hinzufügen"', (tester) async {
      await pumpCall(tester, {..._person(connectedAgoSec: -1), 'state': 'ringing'});

      expect(find.text('Klingelt…'), findsOneWidget);
      await openMore(tester);
      await tester.tap(find.text('Rückfrage'));
      await tester.pumpAndSettle();
      expect(find.text('Anruf hinzufügen'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('Weiterleiten offers blind and consultation transfer', (tester) async {
      await pumpCall(tester, _person());
      await tester.tap(find.text('Weiterleiten'));
      await tester.pumpAndSettle();
      expect(find.text('Weiterleiten an'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('hang-up calls native hangup', (tester) async {
      await pumpCall(tester, _person());
      expect(find.bySemanticsLabel('Auflegen'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hangup')));
      await tester.pump();
      expect(sip.callsTo('hangup'), hasLength(1));
      await dispose(tester);
    });
  });

  group('stale call end', () {
    CallStateEvent ended(String id) =>
        CallStateEvent(callId: id, direction: 'outgoing', state: 'disconnected', disconnectReason: '');

    testWidgets('previous call disconnected → new call answered → screen stays', (tester) async {
      // The listener keeps the last end; the next call's states clear it.
      sip = FakeSip({})..install();
      CallEvents.instance.start();
      sip.emit({'type': 'callState', 'callId': '1', 'direction': 'outgoing', 'state': 'disconnected'});
      await tester.pump();
      expect(CallEvents.instance.lastDisconnected?.callId, '1');
      sip.emit({'type': 'callState', 'callId': '2', 'direction': 'incoming', 'state': 'ringing'});
      await tester.pump();
      expect(CallEvents.instance.lastDisconnected, isNull);

      await pumpCall(tester, _person());
      await settle(tester);
      expect(find.text('Oma Erika'), findsOneWidget);
      expect(find.textContaining('Anruf beendet'), findsNothing);
      await dispose(tester);
    });

    testWidgets('stale end event while a call is live (Zurück banner): screen stays', (tester) async {
      CallEvents.instance.lastDisconnected = ended('old');
      await pumpCall(tester, _person());
      await settle(tester);
      expect(find.textContaining('Anruf beendet'), findsNothing);
      expect(CallEvents.instance.lastDisconnected, isNull);
      await dispose(tester);
    });

    testWidgets('call ended before the screen subscribed and none is live: leaves', (tester) async {
      CallEvents.instance.lastDisconnected = ended('gone');
      await pumpCall(tester, null);
      await settle(tester);
      expect(find.text('Anruf beendet'), findsOneWidget);
      CallEvents.instance.lastDisconnected = null;
      await dispose(tester);
    });
  });

  group('native failures', () {
    Object? fail(Object? _) => throw PlatformException(code: 'ERR');

    testWidgets('hang-up failure keeps the screen and explains', (tester) async {
      await pumpCall(tester, _person());
      sip.responses['hangup'] = fail;
      await tester.tap(find.byKey(const Key('hangup')));
      await tester.pump();
      expect(find.text('Auflegen fehlgeschlagen – bitte erneut versuchen'), findsOneWidget);
      expect(find.text('Oma Erika'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('mute and hold failures keep the state and show a SnackBar', (tester) async {
      await pumpCall(tester, _person());
      sip.responses['mute'] = fail;
      sip.responses['hold'] = fail;
      await tester.tap(find.text('Stumm'));
      await tester.pump();
      expect(control(tester, 'mute').active, isFalse);
      expect(find.text('Stummschalten fehlgeschlagen'), findsOneWidget);
      await tester.tap(find.text('Halten'));
      await tester.pump();
      expect(find.text('Halten'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('transfer failure is reported', (tester) async {
      await pumpCall(tester, _person());
      sip.responses['transfer'] = fail;
      await tester.tap(find.text('Weiterleiten'));
      await tester.pumpAndSettle();
      final sheet = find.byType(TransferSheet);
      for (final d in ['1', '3']) {
        await tester.tap(find.descendant(of: sheet, matching: find.text(d)));
        await tester.pump();
      }
      await tester.tap(find.text('Sofort weiterleiten'));
      await tester.pumpAndSettle();
      expect(find.text('Weiterleiten an 13 fehlgeschlagen'), findsOneWidget);
      await dispose(tester);
    });
  });

  group('two lines', () {
    testWidgets('held line: compact card with Tauschen, Zusammenführen and Verbinden', (tester) async {
      final call = {..._person(), 'other': {..._call(connectedAgoSec: 62), 'number': '13', 'name': 'Test', 'onHold': true}};
      await pumpCall(tester, call);

      expect(find.text('Test'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^gehalten · 01:0[23]$')), findsOneWidget);
      expect(find.bySemanticsLabel('Gehalten: Test'), findsOneWidget);
      expect(find.text('Zusammenführen'), findsOneWidget);
      // The held card sits above the main caller.
      expect(tester.getTopLeft(find.byKey(const Key('second-call'))).dy,
          lessThan(tester.getTopLeft(find.text('Oma Erika')).dy));
      for (final entry in {'swap': 'swapCalls', 'connect': 'transferAttended', 'merge': 'mergeCalls'}.entries) {
        await tester.tap(find.byKey(Key(entry.key)));
        await tester.pump();
        expect(sip.callsTo(entry.value), hasLength(1), reason: entry.value);
      }
      await dispose(tester);
    });

    testWidgets('call waiting: answer / reject; Rückfrage disabled with a reason', (tester) async {
      final call = {..._person(), 'other': {..._call(), 'number': '13', 'name': 'Test', 'state': 'waiting'}};
      await pumpCall(tester, call);

      expect(find.text('Anklopfen: Test'), findsOneWidget);
      expect(find.byKey(const Key('merge')), findsNothing);
      await tester.tap(find.byKey(const Key('answer-waiting')));
      await tester.pump();
      expect(sip.callsTo('answerWaiting'), hasLength(1));
      await tester.tap(find.byKey(const Key('reject-waiting')));
      await tester.pump();
      expect(sip.callsTo('rejectWaiting'), hasLength(1));

      await openMore(tester);
      expect(find.text('Zweite Leitung belegt'), findsOneWidget);
      await tester.tap(find.text('Rückfrage'));
      await tester.pumpAndSettle();
      expect(find.text('Anruf hinzufügen'), findsNothing);
      await dispose(tester);
    });

    testWidgets('conference: partner card without line actions; Konferenz tile disabled', (tester) async {
      final call = {..._person(), 'conference': true, 'other': {..._call(), 'number': '13', 'name': 'Test'}};
      await pumpCall(tester, call);

      expect(find.bySemanticsLabel('Konferenz mit Test'), findsOneWidget);
      expect(find.byKey(const Key('swap')), findsNothing);
      expect(find.byKey(const Key('merge')), findsNothing);
      await openMore(tester);
      expect(find.text('Läuft bereits'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('Mehr → Konferenz merges a held line', (tester) async {
      final call = {..._person(), 'other': {..._call(), 'number': '13', 'name': 'Test', 'onHold': true}};
      await pumpCall(tester, call);
      await openMore(tester);
      await tester.tap(find.text('Konferenz'));
      await tester.pumpAndSettle();
      expect(sip.callsTo('mergeCalls'), hasLength(1));
      await dispose(tester);
    });
  });

  group('door call', () {
    testWidgets('video card with name chip, door grid; without webhook the DTMF code is sent', (tester) async {
      await pumpCall(tester, _call(doorCode: '*1'));

      expect(find.byType(CallVideoCard), findsOneWidget);
      expect(find.text('türklingel'), findsNWidgets(2), reason: 'chip + title');
      expect(find.text('Türstation'), findsOneWidget);
      expect(find.text('TLS'), findsOneWidget);
      for (final label in ['Stumm', 'Lautsprecher', 'Tür öffnen', 'Tastatur', 'Weiterleiten', 'Mehr']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Halten'), findsNothing);

      await tester.tap(find.text('Tür öffnen'));
      await tester.pump();
      expect(sip.callsTo('openDoor'), hasLength(1));
      expect(find.text('Tür-Code gesendet'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('with door_open_remote "Tür öffnen" uses the webhook: green for 2 s, no DTMF', (tester) async {
      final pbx = FakePbx({
        'GET /api/mobile/directory': (_) => jsonResponse({
              'extensions': [
                {'number': '16', 'name': 'türklingel', 'door_open_code': '*1', 'door_open_remote': true},
              ],
            }),
        'POST /api/mobile/door-open': (_) => jsonResponse({'success': true}),
      });
      final dir = await directory(tester, pbx);
      await pumpCall(tester, _call(doorCode: '*1'), dir: dir, opener: DoorOpener(api: pbx.api, authLoader: testAuthLoader));

      await tester.tap(find.text('Tür öffnen'));
      await settle(tester);
      expect(jsonDecode(pbx.to('POST', '/api/mobile/door-open').single.body), {'extension': '16'});
      expect(sip.callsTo('openDoor'), isEmpty);
      expect(find.text('Tür geöffnet ✓'), findsOneWidget);
      expect(control(tester, 'door-open').tone, CallControlTone.done);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Tür öffnen'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('webhook 404 falls back to the DTMF code', (tester) async {
      final pbx = FakePbx({
        'GET /api/mobile/directory': (_) => jsonResponse({
              'extensions': [
                {'number': '16', 'name': 'türklingel', 'door_open_code': '*1', 'door_open_remote': true},
              ],
            }),
        'POST /api/mobile/door-open': (_) => http.Response('{}', 404),
      });
      final dir = await directory(tester, pbx);
      await pumpCall(tester, _call(doorCode: '*1'), dir: dir, opener: DoorOpener(api: pbx.api, authLoader: testAuthLoader));

      await tester.tap(find.text('Tür öffnen'));
      await settle(tester);
      expect(pbx.to('POST', '/api/mobile/door-open'), hasLength(1));
      expect(sip.callsTo('openDoor'), hasLength(1));
      expect(find.text('Tür-Code gesendet'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('first HA action on the grid, the others in Mehr, run by index', (tester) async {
      final call = {..._call(doorCode: '*1'), 'doorActions': ['Licht', 'Garage']};
      await pumpCall(tester, call);

      expect(find.text('Licht'), findsOneWidget);
      expect(find.text('Weiterleiten'), findsNothing);
      await tester.tap(find.byKey(const Key('door-action-0')));
      await tester.pump();
      expect(sip.callsTo('runDoorAction').single.arguments, {'number': '16', 'index': 0});
      expect(find.text('Licht: erledigt'), findsOneWidget);

      await openMore(tester);
      expect(find.text('Weiterleiten'), findsOneWidget, reason: 'moved into Mehr');
      await tester.tap(find.byKey(const Key('door-action-1')));
      await tester.pumpAndSettle();
      expect(sip.callsTo('runDoorAction').last.arguments, {'number': '16', 'index': 1});
      // Queued behind the first SnackBar.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Garage: erledigt'), findsOneWidget);
      await dispose(tester);
    });
  });

  group('audio', () {
    testWidgets('Lautsprecher toggles directly without Bluetooth', (tester) async {
      await pumpCall(tester, _person());

      await tester.tap(find.text('Lautsprecher'));
      await tester.pump();
      expect(sip.callsTo('setAudioRoute').single.arguments, 'speaker');

      sip.emit({'type': 'audioRoute', ..._routes('speaker', ['earpiece', 'speaker'])});
      await tester.pump();
      expect(control(tester, 'audio').active, isTrue);
      await dispose(tester);
    });

    testWidgets('with Bluetooth the Audio button opens the route picker', (tester) async {
      await pumpCall(tester, _person(),
          routes: _routes('bluetooth', ['earpiece', 'speaker', 'bluetooth'], names: {'bluetooth': 'Pixel Buds'}));

      expect(find.bySemanticsLabel('Audio-Ausgabe: Pixel Buds'), findsOneWidget);
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();
      expect(find.text('AUDIO-AUSGABE'), findsOneWidget);
      expect(find.text('Pixel Buds'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await tester.tap(find.text('Lautsprecher'));
      await tester.pumpAndSettle();
      expect(sip.callsTo('setAudioRoute').single.arguments, 'speaker');
      await dispose(tester);
    });

    testWidgets('Mehr lists the audio outputs inline by device name', (tester) async {
      await pumpCall(tester, _person(),
          routes: _routes('bluetooth', ['bluetooth', 'earpiece', 'speaker'], names: {'bluetooth': 'Pixel Buds'}));
      await openMore(tester);

      expect(find.text('Pixel Buds'), findsOneWidget);
      expect(find.text('Hörer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('audio-route-earpiece')));
      await tester.pumpAndSettle();
      expect(sip.callsTo('setAudioRoute').single.arguments, 'earpiece');
      expect(find.text('Mehr im Gespräch'), findsNothing);
      await dispose(tester);
    });
  });

  testWidgets('Mehr → Anruf-Info shows number, direction and encryption', (tester) async {
    await pumpCall(tester, _person());
    await openMore(tester);
    expect(find.text('Direkt weiterleiten'), findsOneWidget);
    expect(find.text('Aufnehmen'), findsNothing, reason: 'recording not allowed');
    await tester.tap(find.text('Anruf-Info'));
    await tester.pumpAndSettle();
    expect(find.text('0171555'), findsWidgets);
    expect(find.text('eingehend'), findsOneWidget);
    expect(find.text('TLS-verschlüsselt'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await dispose(tester);
  });

  testWidgets('Mehr → Direkt weiterleiten opens the blind transfer sheet', (tester) async {
    await pumpCall(tester, _person());
    await openMore(tester);
    await tester.tap(find.text('Direkt weiterleiten'));
    await tester.pumpAndSettle();
    expect(find.text('Direkt weiterleiten an'), findsOneWidget);
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
      final dir = await directory(tester, pbx);
      final recordings = RecordingsRepository(api: pbx.api, authLoader: testAuthLoader);
      await pumpCall(tester, call ?? _person(), dir: dir, recordings: recordings);
    }

    Future<void> tapRecord(WidgetTester tester) async {
      await openMore(tester);
      await tester.tap(find.byKey(const Key('record')));
      await tester.pumpAndSettle();
      await settle(tester);
    }

    testWidgets('no Aufnehmen tile unless the admin allows recording', (tester) async {
      await pumpRecording(tester, allowed: false);
      await openMore(tester);
      expect(find.text('Aufnehmen'), findsNothing);
      expect(find.text('Rückfrage'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('Aufnehmen starts: red REC chip with timer, Stopp ends it', (tester) async {
      await pumpRecording(tester, allowed: true);
      expect(find.byKey(const Key('recording-indicator')), findsNothing);

      await tapRecord(tester);
      expect(jsonDecode(pbx.to('POST', '/api/mobile/recording').single.body), {'action': 'start', 'peer': '0171555'});
      expect(find.byKey(const Key('recording-indicator')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^REC 00:0\d$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Aufnahme läuft')), findsOneWidget);

      await openMore(tester);
      expect(find.text('Stopp'), findsOneWidget);
      await tester.tap(find.byKey(const Key('record')));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(jsonDecode(pbx.to('POST', '/api/mobile/recording').last.body), {'action': 'stop', 'peer': '0171555'});
      expect(find.byKey(const Key('recording-indicator')), findsNothing);
      await dispose(tester);
    });

    testWidgets('door call: REC chip sits on the video card', (tester) async {
      await pumpRecording(tester, allowed: true, call: _call(doorCode: '*1'));
      await tapRecord(tester);
      expect(
        find.descendant(of: find.byType(CallVideoCard), matching: find.byKey(const Key('recording-indicator'))),
        findsOneWidget,
      );
      await dispose(tester);
    });

    testWidgets('403 from the PBX shows a German SnackBar, no chip', (tester) async {
      await pumpRecording(tester, allowed: true, onRecording: (_) => http.Response('{}', 403));
      await tapRecord(tester);
      expect(find.text('Gesprächsaufzeichnung ist für deine Nebenstelle nicht freigegeben.'), findsOneWidget);
      expect(find.byKey(const Key('recording-indicator')), findsNothing);
      await dispose(tester);
    });

    testWidgets('409 on start explains that no unique call was found', (tester) async {
      await pumpRecording(tester, allowed: true, onRecording: (_) => http.Response('{}', 409));
      await tapRecord(tester);
      expect(find.text('Aufnahme nicht gestartet – Gespräch auf der Anlage nicht eindeutig gefunden.'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('disabled with a reason until the call is answered', (tester) async {
      await pumpRecording(tester, allowed: true, call: {..._person(connectedAgoSec: -1), 'state': 'ringing'});
      await openMore(tester);
      expect(find.text('Erst nach dem Annehmen'), findsOneWidget);
      await tester.tap(find.byKey(const Key('record')));
      await tester.pumpAndSettle();
      expect(pbx.to('POST', '/api/mobile/recording'), isEmpty);
      await dispose(tester);
    });

    testWidgets('chip follows the line on screen when swapping lines', (tester) async {
      final lineA = _person();
      final lineB = {..._call(connectedAgoSec: 30), 'number': '13', 'name': 'Test'};
      await pumpRecording(tester, allowed: true, call: {...lineA, 'other': {...lineB, 'onHold': true}});
      await tapRecord(tester);
      expect(find.byKey(const Key('recording-indicator')), findsOneWidget);

      // Tauschen: 13 comes to the front, 0171555 (still recorded on the PBX) is held.
      sip.responses['getCurrentCall'] = (_) => {...lineB, 'other': {...lineA, 'onHold': true}};
      sip.emit({'type': 'callState', 'callId': '1', 'direction': 'incoming', 'state': 'confirmed'});
      await settle(tester);
      expect(find.byKey(const Key('recording-indicator')), findsNothing);

      sip.responses['getCurrentCall'] = (_) => {...lineA, 'other': {...lineB, 'onHold': true}};
      sip.emit({'type': 'callState', 'callId': '1', 'direction': 'incoming', 'state': 'confirmed'});
      await settle(tester);
      expect(find.byKey(const Key('recording-indicator')), findsOneWidget);
      await dispose(tester);
    });
  });

  group('layout and accessibility', () {
    final layouts = <String, Map<String, Object?>>{
      'normal': _person(),
      'two lines': {..._person(), 'other': {..._call(), 'number': '13', 'name': 'Test', 'onHold': true}},
      'door': {..._call(doorCode: '*1'), 'doorActions': ['Licht an']},
    };
    const sizes = {'320 dp': Size(320, 640), 'phone': Size(412, 915)};

    for (final layout in layouts.entries) {
      for (final size in sizes.entries) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('${layout.key}, ${size.key}, text ×$scale: no overflow, all controls reachable', (tester) async {
            await pumpCall(tester, layout.value, size: size.value, textScale: scale);
            expect(tester.takeException(), isNull);

            final labels = layout.key == 'door'
                ? ['Stumm', 'Lautsprecher', 'Tür öffnen', 'Tastatur', 'Licht an', 'Mehr']
                : ['Stumm', 'Lautsprecher', 'Halten', 'Tastatur', 'Weiterleiten', 'Mehr'];
            for (final label in labels) {
              expect(find.bySemanticsLabel(label == 'Mehr' ? 'Mehr Funktionen' : label), findsOneWidget, reason: label);
            }
            // Hang-up is always reachable (scrolls into view with large text).
            await tester.ensureVisible(find.byKey(const Key('hangup')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const Key('hangup')));
            await tester.pump();
            expect(sip.callsTo('hangup'), hasLength(1));
            expect(tester.takeException(), isNull);
            await dispose(tester);
          });
        }
      }
    }

    testWidgets('touch targets ≥ 48 dp and labelled (normal + two lines + door)', (tester) async {
      for (final call in layouts.values) {
        final handle = tester.ensureSemantics();
        await pumpCall(tester, call, size: const Size(320, 640));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
        await dispose(tester);
        sip.uninstall();
      }
    });

    testWidgets('Mehr sheet at text ×2.0 on 320 dp: no overflow, tiles reachable', (tester) async {
      await pumpCall(tester, _person(), size: const Size(320, 640), textScale: 2.0);
      await tester.ensureVisible(find.byKey(const Key('more')));
      await tester.pumpAndSettle();
      await openMore(tester);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Anruf-Info'));
      await tester.pumpAndSettle();
      expect(find.text('Anruf-Info'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await dispose(tester);
    });

    testWidgets('light theme renders the same layout', (tester) async {
      await pumpCall(tester, _call(doorCode: '*1'), theme: AppTheme.light());
      expect(find.text('Tür öffnen'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await dispose(tester);
    });
  });
}
