import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/forwarding_repository.dart';
import 'package:ha_phone_test/services/presence_repository.dart';
import 'package:ha_phone_test/services/ring_settings_repository.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/widgets/status_panel.dart';
import 'package:ha_phone_test/widgets/status_sheet.dart';

import '../helpers/fake_api.dart';
import '../helpers/fake_sip.dart';
import '../helpers/semantics.dart';

void main() {
  late FakeSip sip;
  late Map<Object?, Object?> stored;
  final now = DateTime(2026, 9, 24, 10);

  setUp(() {
    stored = {'enabled': true, 'mutedUntil': 0, 'allowDoor': true};
    sip = FakeSip({
      'getRingPolicy': (_) => stored,
      'setRingPolicy': (args) => stored = Map<Object?, Object?>.from(args as Map),
    })
      ..install();
  });
  tearDown(() => sip.uninstall());

  FakePbx pbx() => FakePbx({
        'GET /api/mobile/directory': (_) => jsonResponse({
              'self': {'number': '18', 'name': 'Emulator-Test', 'presence': 'available'},
              'pbx_version': '0.7.116',
              'extensions': [
                {'number': '18', 'name': 'Emulator-Test'},
              ],
            }),
        'GET /api/mobile/presence': (_) => jsonResponse({
              'self': {'number': '18', 'presence': 'available', 'line': 'idle'},
              'extensions': [],
            }),
        'PUT /api/mobile/presence': (req) => jsonResponse({'presence': (jsonDecode(req.body) as Map)['status']}),
        'GET /api/mobile/forwarding': (_) => jsonResponse({
              'rules': [
                for (final d in ['internal', 'external'])
                  {'status': 'away', 'direction': d, 'mode': 'ring_then_dest', 'dest_type': 'voicemail', 'dest_target': 18, 'ring_timeout': 20},
                for (final d in ['internal', 'external'])
                  {'status': 'do_not_disturb', 'direction': d, 'mode': 'always_dest', 'dest_type': 'voicemail', 'dest_target': 18},
              ],
            }),
      });

  Future<({RingSettingsRepository ring, FakePbx fake, List<int> opened})> pump(WidgetTester tester,
      {double textScale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = pbx();
    final dir = DirectoryRepository(api: fake.api, authLoader: testAuthLoader);
    final presence = PresenceRepository(api: fake.api, authLoader: testAuthLoader, pollInterval: const Duration(hours: 1));
    final forwarding = ForwardingRepository(api: fake.api, authLoader: testAuthLoader);
    final ring = RingSettingsRepository(clock: () => now);
    final opened = <int>[];
    await tester.runAsync(() async {
      await dir.refresh();
      await presence.refresh();
      await forwarding.refresh();
      await ring.load();
    });
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: const Size(390, 844)),
        child: Scaffold(
          body: ListView(children: [
            StatusPanel(
              directory: dir,
              presence: presence,
              forwarding: forwarding,
              ring: ring,
              onOpenForwarding: () => opened.add(1),
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return (ring: ring, fake: fake, opened: opened);
  }

  /// Unmounts and frees the mute-expiry timer (a pending Timer fails the test).
  Future<void> done(WidgetTester tester, RingSettingsRepository ring) async {
    await tester.pumpWidget(const SizedBox());
    ring.dispose();
  }

  testWidgets('header, four status rows with sub-lines from the forwarding rules', (tester) async {
    final t = await pump(tester);
    expect(find.text('Emulator-Test'), findsOneWidget);
    expect(find.text('Nebenstelle 18 · HA-Phone 0.7.116'), findsOneWidget);
    for (final label in ['Verfügbar', 'Abwesend', 'Nicht stören', 'Feierabend']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Mittagspause'), findsNothing);
    expect(find.text('Nach 20 s zur Mailbox'), findsWidgets);
    expect(find.text('Sofort zur Mailbox'), findsOneWidget);
    expect(find.text('Klingeln auf diesem Handy'), findsOneWidget);
    expect(find.text('Türklingel trotzdem'), findsOneWidget);
    expect(find.text('1 Std'), findsOneWidget);
    expect(find.text('bis 17:00'), findsOneWidget);
    expect(find.text('bis morgen'), findsOneWidget);

    await tester.tap(find.byKey(const Key('status-forwarding')));
    expect(t.opened, [1]);
    await done(tester, t.ring);
  });

  testWidgets('TalkBack: forwarding card opens via semantics tap', (tester) async {
    final handle = tester.ensureSemantics();
    final t = await pump(tester);
    semanticsAction(tester, find.byKey(const Key('status-forwarding')));
    expect(t.opened, [1]);
    handle.dispose();
    await done(tester, t.ring);
  });

  testWidgets('TalkBack: Erreichbarkeit row opens via semantics tap', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: ReachabilityLinkCard(hasProblems: true, onTap: () => taps++)),
    ));
    semanticsAction(tester, find.byKey(const Key('status-reachability')));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('tapping a status stores it on the PBX', (tester) async {
    final t = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('status-away')));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();
    final put = t.fake.to('PUT', '/api/mobile/presence').single;
    expect(jsonDecode(put.body), {'status': 'away'});
    await done(tester, t.ring);
  });

  testWidgets('ring switch and mute chips are stored natively', (tester) async {
    final t = await pump(tester);
    expect(tester.widget<Switch>(find.byKey(const Key('ring-switch'))).value, isTrue);

    await tester.tap(find.byKey(const Key('ring-switch')));
    await tester.pumpAndSettle();
    expect(stored['enabled'], false);
    expect(find.text('stumm, bis du es wieder einschaltest · Türklingel klingelt trotzdem'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mute-bis 17:00')));
    await tester.pumpAndSettle();
    expect(stored['enabled'], true);
    expect(stored['mutedUntil'], DateTime(2026, 9, 24, 17).millisecondsSinceEpoch);
    expect(find.text('stumm bis 17:00 · Türklingel klingelt trotzdem'), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(const Key('ring-switch'))).value, isFalse);

    await tester.tap(find.byKey(const Key('ring-door-switch')));
    await tester.pumpAndSettle();
    expect(stored['allowDoor'], false);

    await tester.tap(find.byKey(const Key('ring-switch')));
    await tester.pumpAndSettle();
    expect(stored, {'enabled': true, 'mutedUntil': 0, 'allowDoor': false});
    await done(tester, t.ring);
  });

  testWidgets('textScale 2.0: no overflow', (tester) async {
    final t = await pump(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.byKey(const Key('status-forwarding')), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const Key('status-forwarding')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await done(tester, t.ring);
  });
}
