import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/extension_status.dart';
import 'package:ha_phone_test/models/presence.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/presence_repository.dart';
import 'package:http/http.dart' as http;

import 'helpers/fake_api.dart';

Map<String, Object?> _presenceBody(String own) => {
      'self': {'number': '12', 'presence': own, 'line': 'idle'},
      'extensions': [
        {'number': '11', 'presence': 'lunch', 'line': 'busy'},
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PresenceRepository repo(FakePbx pbx) => PresenceRepository(
        api: pbx.api,
        authLoader: testAuthLoader,
        pollInterval: const Duration(hours: 1),
      );

  test('refresh stores the snapshot', () async {
    final r = repo(FakePbx({'GET /api/mobile/presence': (_) => jsonResponse(_presenceBody('away'))}));
    await r.refresh();
    expect(r.snapshot?.self?.presence, Presence.away);
    expect(r.statusFor('11'), const ExtensionStatus(presence: Presence.lunch, line: LineState.busy));
    expect(r.error, isNull);
  });

  test('404 marks the feature as unsupported', () async {
    final r = repo(FakePbx({}));
    await r.refresh();
    expect(r.isUnsupported, isTrue);
    expect(r.snapshot, isNull);
  });

  test('setOwn updates optimistically and keeps the stored value', () async {
    final r = repo(FakePbx({
      'GET /api/mobile/presence': (_) => jsonResponse(_presenceBody('available')),
      'PUT /api/mobile/presence': (_) => jsonResponse({'number': '12', 'presence': 'lunch'}),
    }));
    await r.refresh();
    final future = r.setOwn(Presence.lunch);
    expect(r.snapshot?.self?.presence, Presence.lunch, reason: 'optimistic');
    await future;
    expect(r.snapshot?.self?.presence, Presence.lunch);
  });

  test('setOwn reverts and rethrows on error', () async {
    final r = repo(FakePbx({
      'GET /api/mobile/presence': (_) => jsonResponse(_presenceBody('available')),
      'PUT /api/mobile/presence': (_) => http.Response('', 422),
    }));
    await r.refresh();
    await expectLater(r.setOwn(Presence.away), throwsA(isA<ApiException>()));
    expect(r.snapshot?.self?.presence, Presence.available);
  });

  test('polls only while visible and in the foreground', () async {
    final pbx = FakePbx({'GET /api/mobile/presence': (_) => jsonResponse(_presenceBody('away'))});
    final r = repo(pbx);
    expect(r.isPolling, isFalse);

    r.setVisible(true);
    expect(r.isPolling, isTrue);
    await pumpEventQueue();
    expect(pbx.requests, hasLength(1), reason: 'fetches immediately when shown');

    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(r.isPolling, isFalse);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(r.isPolling, isTrue);

    r.setVisible(false);
    expect(r.isPolling, isFalse);
    r.dispose();
  });
}
