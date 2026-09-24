import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/forwarding.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/forwarding_repository.dart';

import 'helpers/fake_api.dart';

const _body = {
  'rules': [
    {
      'status': 'lunch',
      'direction': 'external',
      'mode': 'always_dest',
      'dest_type': 'voicemail',
      'dest_target': 12,
      'ring_timeout': 20,
    },
    {
      'status': 'away',
      'direction': 'internal',
      'mode': 'ring_then_dest',
      'dest_type': 'ring_group',
      'dest_target': 3,
      'ring_timeout': 90,
    },
    {
      'status': 'off_work',
      'direction': 'internal',
      'mode': 'ring_then_dest',
      'dest_type': 'extension',
      'dest_target': 11,
      'ring_timeout': 20,
    },
  ],
};

String _names(String n) => n == '11' ? 'sandro' : '';

void main() {
  test('JSON round-trip keeps every field and int targets', () {
    final rules = parseForwardingRules(_body);
    expect(rules, hasLength(3));
    expect(rules[0].status, 'lunch');
    expect(rules[0].direction, ForwardDirection.external);
    expect(rules[0].mode, ForwardMode.alwaysDest);
    expect(rules[0].destType, ForwardDestType.voicemail);
    expect(rules[0].destTarget, '12');
    expect(forwardingRulesToJson(rules), _body);
  });

  test('hangup rules send dest_target 0 (the PBX expects an int)', () {
    const rule = ForwardingRule(
      status: 'do_not_disturb',
      direction: ForwardDirection.internal,
      mode: ForwardMode.alwaysDest,
      destType: ForwardDestType.hangup,
    );
    expect(rule.toJson()['dest_target'], 0);
  });

  test('German descriptions', () {
    final rules = parseForwardingRules(_body);
    expect(describeRule(null, _names), 'Normal klingeln');
    expect(describeRule(rules[0], _names), 'Sofort zur Mailbox');
    expect(describeRule(rules[1], _names), 'Nach 90 s zur Klingelgruppe');
    expect(describeRule(rules[2], _names), 'Nach 20 s zu 11 · sandro');
    const reject = ForwardingRule(
      status: 'away',
      direction: ForwardDirection.external,
      mode: ForwardMode.alwaysDest,
      destType: ForwardDestType.hangup,
    );
    expect(describeRule(reject, _names), 'Ablehnen');
    const toUnknown = ForwardingRule(
      status: 'away',
      direction: ForwardDirection.external,
      mode: ForwardMode.alwaysDest,
      destType: ForwardDestType.extension,
      destTarget: '42',
    );
    expect(describeRule(toUnknown, _names), 'Sofort zu 42');
  });

  test('replaceRule swaps one rule, adds new ones, removes on null, keeps ring groups', () {
    final rules = parseForwardingRules(_body);
    const edited = ForwardingRule(
      status: 'lunch',
      direction: ForwardDirection.external,
      mode: ForwardMode.ringThenDest,
      destType: ForwardDestType.extension,
      destTarget: '11',
      ringTimeout: 30,
    );
    final replaced = replaceRule(rules, 'lunch', ForwardDirection.external, edited);
    expect(replaced, hasLength(3));
    expect(replaced[0], same(edited));
    expect(replaced[1], same(rules[1]));

    final added = replaceRule(rules, 'lunch', ForwardDirection.internal, edited);
    expect(added, hasLength(4));

    final removed = replaceRule(rules, 'off_work', ForwardDirection.internal, null);
    expect(removed.map((r) => r.status), ['lunch', 'away']);
    expect(rules, hasLength(3), reason: 'input list untouched');
  });

  test('editing PUTs the full list with the ring-group rule unchanged', () async {
    final fake = FakePbx({
      'GET /api/mobile/forwarding': (_) => jsonResponse(_body),
      'PUT /api/mobile/forwarding': (req) => jsonResponse(jsonDecode(req.body) as Object),
    });
    final repo = ForwardingRepository(api: fake.api, authLoader: testAuthLoader);
    await repo.refresh();

    await repo.setRule('lunch', ForwardDirection.external, null);

    final put = fake.to('PUT', '/api/mobile/forwarding').single;
    expect(put.headers['X-Device-Token'], 't');
    final sent = (jsonDecode(put.body) as Map<String, dynamic>)['rules'] as List;
    expect(sent, [_body['rules']![1], _body['rules']![2]]);
    expect(repo.rules, hasLength(2));
  });

  test('failed save reverts and rethrows', () async {
    final fake = FakePbx({
      'GET /api/mobile/forwarding': (_) => jsonResponse(_body),
      'PUT /api/mobile/forwarding': (_) => jsonResponse({'detail': 'bad'}, 422),
    });
    final repo = ForwardingRepository(api: fake.api, authLoader: testAuthLoader);
    await repo.refresh();

    await expectLater(
      repo.setRule('lunch', ForwardDirection.external, null),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)),
    );
    expect(repo.rules, hasLength(3));
  });

  test('older PBX (404) names HA-Phone 0.7.110', () async {
    final repo = ForwardingRepository(api: FakePbx({}).api, authLoader: testAuthLoader);
    await repo.refresh();
    expect(repo.isUnsupported, isTrue);
    expect(repo.error!.message, 'Funktion braucht HA-Phone 0.7.110 oder neuer.');
  });

  test('a GET that started before a PUT and ends after it does not overwrite the saved rules', () async {
    final slowGet = Completer<http.Response>();
    var gets = 0;
    final client = MockClient((req) async {
      if (req.method == 'GET') {
        gets++;
        return gets == 1 ? jsonResponse(_body) : slowGet.future;
      }
      return jsonResponse(jsonDecode(req.body) as Object);
    });
    final repo = ForwardingRepository(api: ApiClient(client: client), authLoader: testAuthLoader);
    await repo.refresh();
    expect(repo.rules, hasLength(3));

    final poll = repo.refresh(); // old state in flight
    await pumpEventQueue();
    await repo.setRule('lunch', ForwardDirection.external, null);
    expect(repo.rules, hasLength(2));
    slowGet.complete(jsonResponse(_body));
    await poll;
    expect(repo.rules, hasLength(2), reason: 'stale poll dropped');
  });
}
