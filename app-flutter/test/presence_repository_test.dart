import 'package:http/testing.dart';
import 'dart:async';
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
    expect(r.updatedAt, isNull);
  });

  test('updatedAt marks when the line states were fetched; a failed poll keeps it', () async {
    var ok = true;
    final r = repo(FakePbx({
      'GET /api/mobile/presence': (_) => ok ? jsonResponse(_presenceBody('away')) : http.Response('', 500),
    }));
    final before = DateTime.now();
    await r.refresh();
    final fetched = r.updatedAt;
    expect(fetched, isNotNull);
    expect(fetched!.isBefore(before), isFalse);

    ok = false;
    await r.refresh();
    expect(r.error, isNotNull);
    expect(r.updatedAt, fetched);

    r.clear();
    expect(r.updatedAt, isNull);
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

  test('a poll that started before a PUT and ends after it does not overwrite the new status', () async {
    final slowGet = Completer<http.Response>();
    var gets = 0;
    final client = MockClient((req) async {
      if (req.method == 'GET') {
        gets++;
        return gets == 1 ? jsonResponse(_presenceBody('available')) : slowGet.future;
      }
      return jsonResponse({'presence': 'away'});
    });
    final r = PresenceRepository(api: ApiClient(client: client), authLoader: testAuthLoader, pollInterval: const Duration(hours: 1));
    await r.refresh();

    final poll = r.refresh();
    await pumpEventQueue();
    await r.setOwn(Presence.away);
    slowGet.complete(jsonResponse(_presenceBody('available')));
    await poll;
    expect(r.snapshot?.self?.presence, Presence.away, reason: 'stale poll dropped');
  });

  test('clear() drops a poll that was in flight', () async {
    final slowGet = Completer<http.Response>();
    final r = PresenceRepository(
        api: ApiClient(client: MockClient((_) => slowGet.future)),
        authLoader: testAuthLoader,
        pollInterval: const Duration(hours: 1));
    final poll = r.refresh();
    await pumpEventQueue();
    r.clear();
    slowGet.complete(jsonResponse(_presenceBody('away')));
    await poll;
    expect(r.snapshot, isNull);
  });

  test('a refresh while a poll is in flight waits for it (pull-to-refresh)', () async {
    final slowGet = Completer<http.Response>();
    var gets = 0;
    final r = PresenceRepository(
        api: ApiClient(client: MockClient((_) {
          gets++;
          return slowGet.future;
        })),
        authLoader: testAuthLoader,
        pollInterval: const Duration(hours: 1));
    final poll = r.refresh();
    await pumpEventQueue();
    var pulled = false;
    final pull = r.refresh().then((_) => pulled = true);
    await pumpEventQueue();
    expect(pulled, isFalse, reason: 'waits for the running poll');
    slowGet.complete(jsonResponse(_presenceBody('away')));
    await Future.wait([poll, pull]);
    expect(pulled, isTrue);
    expect(gets, 1);
    expect(r.snapshot?.self?.presence, Presence.away);
  });
}
