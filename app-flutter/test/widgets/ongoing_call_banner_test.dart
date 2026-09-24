import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/call_launcher.dart';
import 'package:ha_phone_test/services/presence_repository.dart';
import 'package:ha_phone_test/widgets/ongoing_call_banner.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_api.dart';
import '../helpers/fake_sip.dart';

Map<String, Object?> _call() => {
      'number': '16',
      'name': 'türklingel',
      'direction': 'incoming',
      'state': 'confirmed',
      'connectedAtMs': DateTime.now().millisecondsSinceEpoch,
    };

void main() {
  late FakeSip sip;

  setUp(() => CallLauncher.requestMicrophone = () async => true);
  tearDown(() => sip.uninstall());

  PresenceRepository presenceWith(String ownLine) => PresenceRepository(
        api: FakePbx({
          'GET /api/mobile/presence': (_) => jsonResponse({
                'self': {'number': '12', 'presence': 'available', 'line': ownLine},
                'extensions': [],
              }),
        }).api,
        authLoader: testAuthLoader,
        pollInterval: const Duration(hours: 1),
      );

  /// Banner over a fake tab that reports the top inset it gets.
  Future<void> pumpBanner(WidgetTester tester, PresenceRepository presence, {Map<String, Object?>? call}) async {
    sip = FakeSip({'getCurrentCall': (_) => call})..install();
    await tester.runAsync(presence.refresh);
    await tester.pumpWidget(MaterialApp(
      routes: {'/active-call': (_) => const Scaffold(body: Text('Gesprächsbildschirm'))},
      home: MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
        child: Scaffold(
          body: OngoingCallBanner(
            presence: presence,
            child: Builder(builder: (context) => Text('inset ${MediaQuery.paddingOf(context).top.round()}')),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('call on another device offers "Hierher holen", which dials *55', (tester) async {
    await pumpBanner(tester, presenceWith('busy'));
    expect(find.text('Gespräch auf anderem Gerät'), findsOneWidget);
    expect(find.text('inset 0'), findsOneWidget, reason: 'the bar covers the status bar');

    await tester.tap(find.text('Hierher holen'));
    await tester.pumpAndSettle();
    expect(sip.callsTo('makeCall').single.arguments, '*55');
    expect(find.text('Gesprächsbildschirm'), findsOneWidget);
  });

  testWidgets('no bar while the own line is idle', (tester) async {
    await pumpBanner(tester, presenceWith('idle'));
    expect(find.byKey(const Key('call-flip')), findsNothing);
    expect(find.byKey(const Key('ongoing-call')), findsNothing);
    expect(find.text('inset 24'), findsOneWidget);
  });

  testWidgets("this app's own call shows the green bar, never the flip offer", (tester) async {
    await pumpBanner(tester, presenceWith('busy'), call: _call());
    expect(find.byKey(const Key('ongoing-call')), findsOneWidget);
    expect(find.text('Gespräch läuft: türklingel'), findsOneWidget);
    expect(find.byKey(const Key('call-flip')), findsNothing);
  });

  testWidgets('right after our own call ended the stale "busy" does not offer a flip', (tester) async {
    final presence = presenceWith('busy');
    await pumpBanner(tester, presence, call: _call());
    expect(find.byKey(const Key('ongoing-call')), findsOneWidget);

    sip.responses['getCurrentCall'] = (_) => null;
    sip.emit({'type': 'callState', 'callId': '1', 'direction': 'incoming', 'state': 'disconnected'});
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
    expect(find.byKey(const Key('ongoing-call')), findsNothing);
    expect(find.byKey(const Key('call-flip')), findsNothing, reason: 'snapshot is from during our call');

    // A poll right after the hang-up is still inside the grace period.
    await tester.runAsync(presence.refresh);
    await tester.pump();
    expect(find.byKey(const Key('call-flip')), findsNothing);
  });

  testWidgets('no flip offer while the PBX is unreachable (stale snapshot)', (tester) async {
    var reachable = true;
    final presence = PresenceRepository(
      api: FakePbx({
        'GET /api/mobile/presence': (_) {
          if (!reachable) throw http.ClientException('offline');
          return jsonResponse({
            'self': {'number': '12', 'line': 'busy'},
            'extensions': [],
          });
        },
      }).api,
      authLoader: testAuthLoader,
      pollInterval: const Duration(hours: 1),
    );
    await pumpBanner(tester, presence);
    expect(find.byKey(const Key('call-flip')), findsOneWidget);

    reachable = false;
    await tester.runAsync(presence.refresh);
    await tester.pump();
    expect(presence.error?.kind, ApiErrorKind.unreachable);
    expect(find.byKey(const Key('call-flip')), findsNothing);
  });
}
