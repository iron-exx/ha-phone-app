import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/voicemail.dart';
import 'package:ha_phone_test/utils/formatters.dart';

void main() {
  group('VoicemailBox.fromJson', () {
    final box = VoicemailBox.fromJson({
      'messages': [
        {
          'id': 'Old/msg0000',
          'new': false,
          'caller_number': '11',
          'caller_name': '',
          'duration_sec': 5,
          'received_at': 1789990000,
        },
        {
          'id': 'INBOX/msg0000',
          'new': true,
          'caller_number': '0301234567',
          'caller_name': 'Pizzeria',
          'duration_sec': 42,
          'received_at': 1790000000,
        },
        {'id': '', 'new': true},
        {'id': 'INBOX/msg0001', 'caller_name': null, 'duration_sec': null, 'received_at': null},
      ],
      'new_count': 1,
    });

    test('parses fields, epoch seconds and sorts newest first', () {
      expect(box.messages.map((m) => m.id), ['INBOX/msg0000', 'Old/msg0000', 'INBOX/msg0001']);
      final m = box.messages.first;
      expect(m.isNew, isTrue);
      expect(m.callerName, 'Pizzeria');
      expect(m.callerNumber, '0301234567');
      expect(m.duration, const Duration(seconds: 42));
      expect(m.receivedAt, DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000));
    });

    test('tolerates nulls and drops messages without id', () {
      final m = box.messages.last;
      expect(m.isNew, isFalse);
      expect(m.callerName, '');
      expect(m.duration, Duration.zero);
      expect(box.messages.length, 3);
    });

    test('missing list gives an empty box', () {
      expect(VoicemailBox.fromJson({}).messages, isEmpty);
    });
  });

  group('splitVoicemailId', () {
    test('splits folder and name', () {
      final p = splitVoicemailId('INBOX/msg0000');
      expect(p?.folder, 'INBOX');
      expect(p?.name, 'msg0000');
    });

    test('rejects malformed or path-escaping ids', () {
      expect(splitVoicemailId('msg0000'), isNull);
      expect(splitVoicemailId('INBOX/../secret'), isNull);
      expect(splitVoicemailId('../INBOX'), isNull);
      expect(splitVoicemailId('INBOX/msg 1'), isNull);
      expect(splitVoicemailId(''), isNull);
    });
  });

  group('countUnheard', () {
    VoicemailMessage msg(String id, {required bool isNew, int at = 1790000000}) => VoicemailMessage(
          id: id,
          isNew: isNew,
          receivedAt: DateTime.fromMillisecondsSinceEpoch(at * 1000),
        );

    test('counts new messages not heard locally', () {
      final messages = [
        msg('INBOX/msg0000', isNew: true),
        msg('INBOX/msg0001', isNew: true),
        msg('Old/msg0000', isNew: false),
      ];
      expect(countUnheard(messages, {}), 2);
      expect(countUnheard(messages, {messages[0].heardKey}), 1);
      expect(countUnheard(messages, {for (final m in messages) m.heardKey}), 0);
    });

    test('a renumbered new message is not hidden by an old heard id', () {
      final heardOld = msg('INBOX/msg0000', isNew: true, at: 1780000000);
      final fresh = msg('INBOX/msg0000', isNew: true, at: 1790000000);
      expect(countUnheard([fresh], {heardOld.heardKey}), 1);
    });
  });

  test('voicemail subtitle', () {
    final now = DateTime(2026, 9, 23, 18);
    expect(voicemailSubtitle(const Duration(seconds: 42), DateTime(2026, 9, 23, 14, 2), now), '0:42 · heute 14:02');
    expect(formatVoicemailTime(DateTime(2026, 9, 22, 9, 5), now), 'gestern 09:05');
    expect(formatVoicemailTime(DateTime(2026, 9, 21, 9, 5), now), 'Mo 09:05');
    expect(formatVoicemailTime(DateTime(2026, 9, 1, 9, 5), now), '01.09. 09:05');
  });
}
