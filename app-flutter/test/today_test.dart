import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/doorbell_event.dart';
import 'package:ha_phone_test/services/sip_channel.dart';
import 'package:ha_phone_test/utils/call_merge.dart';
import 'package:ha_phone_test/utils/today.dart';

final _now = DateTime(2026, 9, 25, 18, 30);

MergedCall _call(String number, DateTime at, {String direction = 'incoming', bool answered = true}) => MergedCall(
      local: CallHistoryEntry(
        id: '$number-${at.millisecondsSinceEpoch}',
        number: number,
        name: '',
        direction: direction,
        answered: answered,
        video: false,
        startedAt: at,
        duration: Duration.zero,
      ),
    );

DoorbellEvent _ring(int id, DateTime at) =>
    DoorbellEvent(id: id, doorNumber: '16', doorName: 'Haustür', startedAt: at);

void main() {
  group('todaySummary', () {
    test('counts only today: calls, missed calls and door rings', () {
      final s = todaySummary(
        [
          _call('11', DateTime(2026, 9, 25, 18)),
          _call('12', DateTime(2026, 9, 25, 9), answered: false),
          _call('13', DateTime(2026, 9, 25, 8), direction: 'outgoing', answered: false),
          _call('14', DateTime(2026, 9, 24, 23, 59), answered: false),
        ],
        [_ring(1, DateTime(2026, 9, 25, 7)), _ring(2, DateTime(2026, 9, 24, 12))],
        _now,
      );
      expect(s.calls, 3);
      expect(s.missed, 1);
      expect(s.doorRings, 1);
      expect(s.isEmpty, isFalse);
    });

    test('is empty on a quiet day', () {
      final s = todaySummary([_call('11', DateTime(2026, 9, 24, 12))], const [], _now);
      expect(s.isEmpty, isTrue);
    });
  });

  group('suggestFavorites', () {
    test('most frequent numbers first, ties by most recent, without excluded ones', () {
      final calls = [
        _call('12', DateTime(2026, 9, 25, 18)),
        _call('11', DateTime(2026, 9, 25, 17)),
        _call('16', DateTime(2026, 9, 25, 16)),
        _call('11', DateTime(2026, 9, 25, 15)),
        _call('0171555', DateTime(2026, 9, 25, 14), direction: 'outgoing'),
        _call('18', DateTime(2026, 9, 25, 13)),
        _call('*43', DateTime(2026, 9, 25, 12), direction: 'outgoing'),
        _call('', DateTime(2026, 9, 25, 11)),
      ];
      expect(suggestFavorites(calls, exclude: {'16', '18'}), ['11', '12', '0171555']);
      expect(suggestFavorites(calls, exclude: {'16', '18'}, limit: 2), ['11', '12']);
    });
  });
}
