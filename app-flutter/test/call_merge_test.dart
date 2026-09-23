import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/pbx_call.dart';
import 'package:ha_phone_test/services/call_history_store.dart';
import 'package:ha_phone_test/services/local_store.dart';
import 'package:ha_phone_test/services/sip_channel.dart';
import 'package:ha_phone_test/utils/call_merge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_api.dart';
import 'helpers/fake_sip.dart';

final _t0 = DateTime(2026, 9, 23, 12);

CallHistoryEntry _local(String id, String number, DateTime at, {String direction = 'incoming', bool answered = true}) =>
    CallHistoryEntry(
      id: id,
      number: number,
      name: '',
      direction: direction,
      answered: answered,
      video: false,
      startedAt: at,
      duration: Duration(seconds: answered ? 30 : 0),
    );

PbxCall _pbx(String id, String number, DateTime at, {String direction = 'incoming', bool answered = true}) => PbxCall(
      id: id,
      number: number,
      name: 'tuer',
      direction: direction,
      answered: answered,
      startedAt: at,
      duration: Duration(seconds: answered ? 12 : 0),
    );

int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses the PBX call log', () {
    final calls = parsePbxCalls({
      'calls': [
        {
          'id': '1790000004.4',
          'number': '16',
          'name': 'tuer',
          'direction': 'incoming',
          'answered': false,
          'started_at': 1790000000,
          'duration_sec': 0,
        },
        {'number': 'no id'},
      ],
    });
    expect(calls, hasLength(1));
    expect(calls.single.missed, isTrue);
    expect(calls.single.startedAt, DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000));
  });

  test('same number + direction within ±30 s is one row', () {
    final merged = mergeCallHistory(
      [_local('a', '16', _t0.add(const Duration(seconds: 29)))],
      [_pbx('p', '16', _t0)],
    );
    expect(merged, hasLength(1));
    expect(merged.single.local?.id, 'a');
    expect(merged.single.pbx?.id, 'p');
    expect(merged.single.isOtherDevice, isFalse);
    expect(merged.single.entry.id, 'a');
  });

  test('outside the window, other direction or number: separate rows', () {
    final merged = mergeCallHistory(
      [
        _local('late', '16', _t0.add(const Duration(seconds: 31))),
        _local('out', '16', _t0, direction: 'outgoing'),
        _local('other', '11', _t0),
      ],
      [_pbx('p', '16', _t0)],
    );
    expect(merged, hasLength(4));
    expect(merged.where((c) => c.pbx != null && c.local == null).single.isOtherDevice, isTrue);
  });

  test('each PBX call pairs with the closest local entry only', () {
    final merged = mergeCallHistory(
      [
        _local('far', '16', _t0.add(const Duration(seconds: 20))),
        _local('near', '16', _t0.add(const Duration(seconds: 2))),
      ],
      [_pbx('p', '16', _t0)],
    );
    expect(merged, hasLength(2));
    expect(merged.firstWhere((c) => c.pbx != null).local?.id, 'near');
  });

  test('PBX-only, local-only, newest first, hidden ids dropped', () {
    final merged = mergeCallHistory(
      [_local('l', '12', _t0.subtract(const Duration(hours: 1)))],
      [
        _pbx('new', '16', _t0, answered: false),
        _pbx('hidden', '11', _t0.subtract(const Duration(minutes: 5))),
      ],
      hiddenPbxIds: {'hidden'},
    );
    expect(merged.map((c) => c.key), ['p-new', 'l-l']);
    expect(merged.first.isOtherDevice, isTrue);
    expect(merged.first.missed, isTrue);
    expect(merged.first.entry.name, 'tuer');
  });

  test('rang here unanswered but taken on the desk phone: not missed', () {
    final merged = mergeCallHistory(
      [_local('l', '16', _t0, answered: false)],
      [_pbx('p', '16', _t0, answered: true)],
    );
    final c = merged.single;
    expect(c.missed, isFalse);
    expect(c.isOtherDevice, isTrue);
    expect(c.entry.answered, isTrue);
    expect(c.entry.duration, const Duration(seconds: 12));
  });

  test('missed count includes PBX-only missed calls', () {
    final merged = mergeCallHistory(
      [_local('l', '0301', _t0, answered: false)],
      [
        _pbx('p1', '16', _t0.add(const Duration(minutes: 1)), answered: false),
        _pbx('p2', '11', _t0.add(const Duration(minutes: 2))),
      ],
    );
    expect(countMergedMissedSince(merged, null), 2);
    expect(countMergedMissedSince(merged, _t0.add(const Duration(seconds: 30))), 1);
  });

  group('CallHistoryStore', () {
    late FakeSip sip;
    final now = DateTime.now();

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      sip = FakeSip({
        'getCallHistory': (_) => [historyEntry(id: '1', number: '12', startedAt: now, direction: 'outgoing')],
      })
        ..install();
    });
    tearDown(() => sip.uninstall());

    FakePbx pbx() => FakePbx({
          'GET /api/mobile/calls': (req) {
            expect(req.url.queryParameters['limit'], '200');
            return jsonResponse({
              'calls': [
                {
                  'id': 'x1',
                  'number': '16',
                  'name': 'tuer',
                  'direction': 'incoming',
                  'answered': false,
                  'started_at': _epoch(now) - 60,
                  'duration_sec': 0,
                },
              ],
            });
          },
        });

    test('merges, counts the PBX missed call, hides deleted PBX entries', () async {
      final store = CallHistoryStore(api: pbx().api, authLoader: testAuthLoader);
      await store.refreshAll();
      expect(store.calls, hasLength(2));
      expect(store.unseenMissed, 1);

      await store.deleteCall(store.calls.firstWhere((c) => c.pbx != null));
      expect(store.calls, hasLength(1));
      expect(sip.callsTo('deleteCallHistoryEntry'), isEmpty, reason: 'PBX rows are only hidden');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(StoreKeys.callsHiddenPbx), ['x1']);

      // A fresh store (app restart) keeps the entry hidden.
      final again = CallHistoryStore(api: pbx().api, authLoader: testAuthLoader);
      await again.refreshAll();
      expect(again.calls.map((c) => c.key), ['l-1']);
    });

    test('Verlauf löschen clears locally and hides all PBX ids', () async {
      final store = CallHistoryStore(api: pbx().api, authLoader: testAuthLoader);
      await store.refreshAll();
      await store.clear();
      expect(store.calls, isEmpty);
      expect(sip.callsTo('clearCallHistory'), hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(StoreKeys.callsHiddenPbx), ['x1']);
    });

    test('PBX offline: local entries stay', () async {
      final store = CallHistoryStore(api: FakePbx({}).api, authLoader: testAuthLoader);
      await store.refreshAll();
      expect(store.calls.map((c) => c.key), ['l-1']);
      expect(store.pbxError, isNotNull);
    });
  });
}
