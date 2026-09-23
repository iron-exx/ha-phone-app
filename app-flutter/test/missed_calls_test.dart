import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/sip_channel.dart';
import 'package:ha_phone_test/utils/missed_calls.dart';

CallHistoryEntry _e(String id, DateTime at, {String direction = 'incoming', bool answered = false}) =>
    CallHistoryEntry(
      id: id,
      number: '11',
      name: '',
      direction: direction,
      answered: answered,
      video: false,
      startedAt: at,
      duration: Duration.zero,
    );

void main() {
  final entries = [
    _e('a', DateTime(2026, 9, 23, 14)),
    _e('b', DateTime(2026, 9, 23, 12), answered: true),
    _e('c', DateTime(2026, 9, 23, 10), direction: 'outgoing'),
    _e('d', DateTime(2026, 9, 22, 9)),
  ];

  test('counts all missed calls when the tab was never opened', () {
    expect(countMissedSince(entries, null), 2);
  });

  test('counts only missed calls after last seen', () {
    expect(countMissedSince(entries, DateTime(2026, 9, 23, 8)), 1);
    expect(countMissedSince(entries, DateTime(2026, 9, 23, 15)), 0);
  });

  test('ignores unanswered outgoing calls', () {
    expect(countMissedSince([entries[2]], null), 0);
  });
}
