import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/sip_channel.dart';
import 'package:ha_phone_test/utils/formatters.dart';

CallHistoryEntry _entry({
  String direction = 'incoming',
  bool answered = true,
  bool video = false,
  int sec = 0,
}) =>
    CallHistoryEntry(
      id: '1',
      number: '11',
      name: '',
      direction: direction,
      answered: answered,
      video: video,
      startedAt: DateTime(2026, 9, 23, 14),
      duration: Duration(seconds: sec),
    );

void main() {
  group('formatCallDuration', () {
    test('formats short calls as m:ss', () {
      expect(formatCallDuration(const Duration(seconds: 41)), '0:41');
      expect(formatCallDuration(const Duration(minutes: 3, seconds: 12)), '3:12');
    });
    test('adds hours when needed', () {
      expect(formatCallDuration(const Duration(hours: 1, minutes: 2, seconds: 5)), '1:02:05');
    });
  });

  group('formatCallTimer', () {
    test('pads minutes to two digits', () {
      expect(formatCallTimer(const Duration(seconds: 7)), '00:07');
      expect(formatCallTimer(const Duration(minutes: 2, seconds: 37)), '02:37');
    });
    test('shows hours for long calls and clamps negatives', () {
      expect(formatCallTimer(const Duration(hours: 1, minutes: 2, seconds: 5)), '1:02:05');
      expect(formatCallTimer(const Duration(seconds: -3)), '00:00');
    });
  });

  group('formatHistoryTime', () {
    // Wednesday, 23.09.2026 14:05
    final now = DateTime(2026, 9, 23, 14, 5);

    test('shows HH:mm for today', () {
      expect(formatHistoryTime(DateTime(2026, 9, 23, 8, 3), now), '08:03');
    });
    test('shows "gestern" for yesterday, even just after midnight', () {
      expect(formatHistoryTime(DateTime(2026, 9, 22, 23, 59), now), 'gestern');
      expect(
        formatHistoryTime(DateTime(2026, 9, 22, 23, 59), DateTime(2026, 9, 23, 0, 1)),
        'gestern',
      );
    });
    test('shows the short weekday within 7 days', () {
      expect(formatHistoryTime(DateTime(2026, 9, 21, 10), now), 'Mo');
      expect(formatHistoryTime(DateTime(2026, 9, 17, 10), now), 'Do');
    });
    test('shows dd.MM. for older calls', () {
      expect(formatHistoryTime(DateTime(2026, 9, 16, 10), now), '16.09.');
      expect(formatHistoryTime(DateTime(2025, 12, 1, 10), now), '01.12.');
    });
    test('handles the DST switch (25 h day)', () {
      // DST ends 25.10.2026 in Germany.
      expect(formatHistoryTime(DateTime(2026, 10, 24, 12), DateTime(2026, 10, 25, 12)), 'gestern');
    });
  });

  group('callSubtitle', () {
    test('describes incoming and outgoing calls with duration', () {
      expect(callSubtitle(_entry(sec: 192)), 'eingehend · 3:12');
      expect(callSubtitle(_entry(direction: 'outgoing', sec: 41)), 'ausgehend · 0:41');
    });
    test('marks missed and unanswered calls', () {
      expect(callSubtitle(_entry(answered: false)), 'verpasst');
      expect(callSubtitle(_entry(direction: 'outgoing', answered: false)), 'ausgehend · nicht erreicht');
    });
    test('appends Video', () {
      expect(callSubtitle(_entry(answered: false, video: true)), 'verpasst · Video');
    });
  });
}
