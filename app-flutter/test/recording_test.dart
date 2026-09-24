import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/extension_status.dart';
import 'package:ha_phone_test/models/recording.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/sip_channel.dart';
import 'package:ha_phone_test/utils/call_flip.dart';
import 'package:ha_phone_test/utils/recording_ui.dart';

void main() {
  group('RecordingList.fromJson', () {
    final list = RecordingList.fromJson({
      'allowed': true,
      'recordings': [
        {'id': '20260923-090000_11', 'peer': '11', 'started_at': 1790000000, 'duration_sec': 5, 'size_bytes': 800},
        {
          'id': '20260924-101500_0171123',
          'peer': '0171123',
          'started_at': 1790100000,
          'duration_sec': 192,
          'size_bytes': 3072044,
        },
        {'id': '', 'peer': '12'},
        {'id': '20260922-080000_', 'peer': null, 'started_at': null, 'duration_sec': null, 'size_bytes': null},
      ],
    });

    test('parses fields, epoch seconds and sorts newest first', () {
      expect(list.allowed, isTrue);
      expect(list.recordings.map((r) => r.id), ['20260924-101500_0171123', '20260923-090000_11', '20260922-080000_']);
      final r = list.recordings.first;
      expect(r.peer, '0171123');
      expect(r.duration, const Duration(minutes: 3, seconds: 12));
      expect(r.sizeBytes, 3072044);
      expect(r.startedAt, DateTime.fromMillisecondsSinceEpoch(1790100000 * 1000));
    });

    test('tolerates nulls and drops entries without id', () {
      final r = list.recordings.last;
      expect(r.peer, '');
      expect(r.duration, Duration.zero);
      expect(r.sizeBytes, 0);
      expect(list.recordings, hasLength(3));
    });

    test('missing fields: not allowed, empty', () {
      final empty = RecordingList.fromJson(const {});
      expect(empty.allowed, isFalse);
      expect(empty.recordings, isEmpty);
    });
  });

  group('isValidRecordingId', () {
    test('accepts the PBX file names', () {
      expect(isValidRecordingId('20260924-101500_0171123'), isTrue);
      expect(isValidRecordingId('20260924-101500_'), isTrue, reason: 'unknown peer');
      expect(isValidRecordingId('20260924-101500_+49171*#'), isTrue);
    });

    test('rejects malformed or path-escaping ids', () {
      expect(isValidRecordingId(''), isFalse);
      expect(isValidRecordingId('20260924-101500'), isFalse);
      expect(isValidRecordingId('../20260924-101500_11'), isFalse);
      expect(isValidRecordingId('20260924-101500_11/../x'), isFalse);
      expect(isValidRecordingId('20260924-101500_11.wav'), isFalse);
      expect(isValidRecordingId('20260924-101500_abc'), isFalse);
      expect(isValidRecordingId('20260924-101500_${'1' * 33}'), isFalse);
    });
  });

  test('recordingPeer trims and respects the 32-character limit', () {
    expect(recordingPeer(' 0171123 '), '0171123');
    expect(recordingPeer('1' * 40), '1' * 32);
  });

  group('RecordingLines', () {
    final t0 = DateTime(2026, 9, 24, 10);
    final lineA = recordingLineKey('11', t0);
    final lineB = recordingLineKey('13', t0.add(const Duration(minutes: 1)));

    test('start and stop per line', () {
      final started = const RecordingLines().started(lineA, t0);
      expect(started.since(lineA), t0);
      expect(started.since(lineB), isNull, reason: 'the other line is not recorded');
      expect(started.stopped(lineA).isEmpty, isTrue);
    });

    test('a later call to the same number is a different line', () {
      final started = const RecordingLines().started(lineA, t0);
      expect(started.since(recordingLineKey('11', t0.add(const Duration(hours: 1)))), isNull);
    });

    test('retain drops ended lines and keeps the rest', () {
      final both = const RecordingLines().started(lineA, t0).started(lineB, t0);
      final onlyB = both.retain({lineB});
      expect(onlyB.since(lineA), isNull);
      expect(onlyB.since(lineB), t0);
      expect(identical(onlyB.retain({lineB}), onlyB), isTrue, reason: 'no change, same instance');
      expect(both.retain(const {}).isEmpty, isTrue);
    });

    test('is immutable', () {
      const empty = RecordingLines();
      empty.started(lineA, t0);
      expect(empty.isEmpty, isTrue);
    });
  });

  test('line keys of a call cover both lines', () {
    final call = CurrentCall.fromMap({
      'number': '11',
      'connectedAtMs': 1000,
      'other': {'number': '13', 'connectedAtMs': 2000},
    });
    expect(lineKeysOf(call), {'11@1000', '13@2000'});
    expect(lineKeysOf(null), isEmpty);
  });

  group('recordingErrorText', () {
    test('maps the PBX answers to German messages', () {
      expect(recordingErrorText(const ApiException(ApiErrorKind.notAllowed, 403), starting: true),
          'Gesprächsaufzeichnung ist für Ihre Nebenstelle nicht freigegeben.');
      expect(recordingErrorText(const ApiException(ApiErrorKind.server, 409), starting: true),
          'Aufnahme nicht gestartet – Gespräch auf der Anlage nicht eindeutig gefunden.');
      expect(recordingErrorText(const ApiException(ApiErrorKind.server, 409), starting: false),
          'Keine laufende Aufnahme gefunden.');
      expect(recordingErrorText(const ApiException(ApiErrorKind.server, 502), starting: false),
          'Anlage konnte die Aufnahme nicht stoppen.');
      expect(recordingErrorText(const ApiException(ApiErrorKind.unreachable), starting: true),
          'Anlage nicht erreichbar – Aufnahme nicht gestartet.');
      expect(recordingErrorText(const ApiException(ApiErrorKind.unsupported, 404, '0.7.114'), starting: true),
          'Funktion braucht HA-Phone 0.7.114 oder neuer.');
    });
  });

  test('recording count text', () {
    expect(recordingCountText(0), 'Keine Aufnahmen');
    expect(recordingCountText(1), '1 Aufnahme');
    expect(recordingCountText(4), '4 Aufnahmen');
  });

  group('shouldOfferCallFlip', () {
    final now = DateTime(2026, 9, 24, 10);

    test('offered while the own line is busy on another device', () {
      expect(shouldOfferCallFlip(ownLine: LineState.busy, hasOwnCall: false, snapshotAt: now), isTrue);
    });

    test('not offered while this app has the call (it makes the line busy too)', () {
      expect(shouldOfferCallFlip(ownLine: LineState.busy, hasOwnCall: true, snapshotAt: now), isFalse);
    });

    test('not offered for other line states or without data', () {
      for (final line in [LineState.idle, LineState.ringing, LineState.offline, LineState.unknown, null]) {
        expect(shouldOfferCallFlip(ownLine: line, hasOwnCall: false, snapshotAt: now), isFalse, reason: '$line');
      }
      expect(shouldOfferCallFlip(ownLine: LineState.busy, hasOwnCall: false, snapshotAt: null), isFalse);
    });

    test('a "busy" snapshot from around the end of our own call is not trusted', () {
      final ended = now;
      bool offer(DateTime at) =>
          shouldOfferCallFlip(ownLine: LineState.busy, hasOwnCall: false, snapshotAt: at, ownCallEndedAt: ended);
      expect(offer(ended.subtract(const Duration(seconds: 5))), isFalse, reason: 'from during our call');
      expect(offer(ended.add(const Duration(seconds: 2))), isFalse, reason: 'PBX may not have seen the hang-up');
      expect(offer(ended.add(kCallFlipGrace + const Duration(seconds: 1))), isTrue);
    });

    test('flip code', () => expect(kCallFlipCode, '*55'));
  });
}
