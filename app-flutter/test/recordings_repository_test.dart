import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/recording.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/recordings_repository.dart';
import 'package:http/http.dart' as http;

import 'helpers/fake_api.dart';

final _body = {
  'allowed': true,
  'recordings': [
    {'id': '20260924-101500_+49171', 'peer': '+49171', 'started_at': 1790100000, 'duration_sec': 60, 'size_bytes': 1},
    {'id': '20260923-090000_11', 'peer': '11', 'started_at': 1790000000, 'duration_sec': 5, 'size_bytes': 1},
  ],
};

final _rec = CallRecording(id: '20260924-101500_+49171', peer: '+49171', startedAt: DateTime(2026));

Future<ApiException> _errorOf(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('expected ApiException');
}

void main() {
  final t0 = DateTime(2026, 9, 24, 10, 15);
  final line = recordingLineKey('+49171', t0);

  RecordingsRepository repo(FakePbx pbx) =>
      RecordingsRepository(api: pbx.api, authLoader: testAuthLoader, clock: () => t0);

  group('ApiClient recording endpoints', () {
    test('start POSTs action and peer with the device headers and returns the id', () async {
      final pbx = FakePbx({
        'POST /api/mobile/recording': (_) => jsonResponse({'recording': true, 'id': '20260924-101500_0171123'}),
      });
      expect(await pbx.api.startRecording(testAuth, '0171123'), '20260924-101500_0171123');
      final req = pbx.requests.single;
      expect(jsonDecode(req.body), {'action': 'start', 'peer': '0171123'});
      expect(req.headers['X-Device-Token'], 't');
      expect(req.headers['Content-Type'], startsWith('application/json'));
    });

    test('403 means "not allowed", 401 still asks for re-pairing', () async {
      final e403 = await _errorOf(() => FakePbx({'POST /api/mobile/recording': (_) => http.Response('', 403)})
          .api
          .startRecording(testAuth, '11'));
      expect(e403.kind, ApiErrorKind.notAllowed);
      expect(e403.needsRepairing, isFalse);
      final e401 = await _errorOf(() => FakePbx({'POST /api/mobile/recording': (_) => http.Response('', 401)})
          .api
          .stopRecording(testAuth, '11'));
      expect(e401.needsRepairing, isTrue);
    });

    test('older PBX: recordings are unsupported below 0.7.114', () async {
      final e = await _errorOf(() => FakePbx({}).api.fetchRecordings(testAuth));
      expect(e.kind, ApiErrorKind.unsupported);
      expect(e.message, 'Funktion braucht HA-Phone 0.7.114 oder neuer.');
      http.Response html(http.Request _) =>
          http.Response('<html></html>', 200, headers: {'content-type': 'text/html; charset=utf-8'});
      final eHtml = await _errorOf(() => FakePbx({'GET /api/mobile/recordings': html}).api.fetchRecordings(testAuth));
      expect(eHtml.kind, ApiErrorKind.unsupported);
    });

    test('audio and delete URLs percent-encode the id', () async {
      final pbx = FakePbx({
        'GET /api/mobile/recordings/20260924-101500_%2B49171/audio': (_) => http.Response.bytes([1, 2], 200),
        'DELETE /api/mobile/recordings/20260924-101500_%2B49171': (_) => jsonResponse({'success': true}),
      });
      expect(pbx.api.recordingAudioUri(testAuth, _rec).toString(),
          'http://box/api/mobile/recordings/20260924-101500_%2B49171/audio');
      expect(await pbx.api.downloadRecording(testAuth, _rec), [1, 2]);
      await pbx.api.deleteRecording(testAuth, _rec);
      expect(pbx.requests, hasLength(2));
    });

    test('deleting an already deleted recording (404) is fine', () async {
      await FakePbx({}).api.deleteRecording(testAuth, _rec);
    });

    test('malformed ids never reach the network', () async {
      final pbx = FakePbx({});
      final bad = CallRecording(id: '../../etc/passwd', startedAt: DateTime(2026));
      expect((await _errorOf(() => pbx.api.deleteRecording(testAuth, bad))).kind, ApiErrorKind.server);
      expect(() => pbx.api.recordingAudioUri(testAuth, bad), throwsA(isA<ApiException>()));
      expect(pbx.requests, isEmpty);
    });
  });

  group('RecordingsRepository', () {
    test('refresh loads the list and the allowed flag', () async {
      final r = repo(FakePbx({'GET /api/mobile/recordings': (_) => jsonResponse(_body)}));
      await r.refresh();
      expect(r.hasLoaded, isTrue);
      expect(r.isAllowed, isTrue);
      expect(r.recordings.map((e) => e.peer), ['+49171', '11']);
    });

    test('older PBX: unsupported, no crash, empty', () async {
      final r = repo(FakePbx({}));
      await r.refresh();
      expect(r.isUnsupported, isTrue);
      expect(r.recordings, isEmpty);
      expect(r.hasLoaded, isFalse);
    });

    test('delete removes the recording after the PBX confirmed', () async {
      final pbx = FakePbx({
        'GET /api/mobile/recordings': (_) => jsonResponse(_body),
        'DELETE /api/mobile/recordings/20260924-101500_%2B49171': (_) => jsonResponse({'success': true}),
      });
      final r = repo(pbx);
      await r.refresh();
      await r.delete(r.recordings.first);
      expect(r.recordings.map((e) => e.id), ['20260923-090000_11']);
    });

    test('failed delete keeps the recording', () async {
      final r = repo(FakePbx({
        'GET /api/mobile/recordings': (_) => jsonResponse(_body),
        'DELETE /api/mobile/recordings/20260924-101500_%2B49171': (_) => http.Response('', 500),
      }));
      await r.refresh();
      await expectLater(r.delete(r.recordings.first), throwsA(isA<ApiException>()));
      expect(r.recordings, hasLength(2));
    });

    test('start marks the line as recorded, stop clears it', () async {
      final pbx = FakePbx({
        'POST /api/mobile/recording': (req) => jsonDecode(req.body)['action'] == 'start'
            ? jsonResponse({'recording': true, 'id': '20260924-101500_+49171'})
            : jsonResponse({'recording': false}),
      });
      final r = repo(pbx);
      await r.start(lineKey: line, peer: '+49171');
      expect(r.recordingSince(line), t0);
      expect(r.isSwitching, isFalse);

      await r.stop(lineKey: line, peer: '+49171');
      expect(r.recordingSince(line), isNull);
      expect(pbx.requests.map((q) => jsonDecode(q.body)['action']), ['start', 'stop']);
    });

    test('failed start (403/409/502) leaves the line unrecorded and rethrows', () async {
      for (final status in [403, 409, 502]) {
        final r = repo(FakePbx({'POST /api/mobile/recording': (_) => http.Response('{}', status)}));
        await expectLater(r.start(lineKey: line, peer: '+49171'), throwsA(isA<ApiException>()), reason: '$status');
        expect(r.recordingSince(line), isNull);
        expect(r.isSwitching, isFalse);
      }
    });

    test('stop answered with 409 (nothing running) clears the indicator anyway', () async {
      var action = 'start';
      final r = repo(FakePbx({
        'POST /api/mobile/recording': (_) => action == 'start'
            ? jsonResponse({'recording': true, 'id': 'x'})
            : http.Response('{"detail":"Keine laufende Aufzeichnung gefunden"}', 409),
      }));
      await r.start(lineKey: line, peer: '+49171');
      action = 'stop';
      final e = await _errorOf(() => r.stop(lineKey: line, peer: '+49171'));
      expect(e.statusCode, 409);
      expect(r.recordingSince(line), isNull);
    });

    test('stop failing with 502 keeps the indicator (still recording)', () async {
      var action = 'start';
      final r = repo(FakePbx({
        'POST /api/mobile/recording': (_) =>
            action == 'start' ? jsonResponse({'recording': true, 'id': 'x'}) : http.Response('{}', 502),
      }));
      await r.start(lineKey: line, peer: '+49171');
      action = 'stop';
      await expectLater(r.stop(lineKey: line, peer: '+49171'), throwsA(isA<ApiException>()));
      expect(r.recordingSince(line), t0);
    });

    test('retainLines forgets ended lines; clear forgets everything', () async {
      final r = repo(FakePbx({
        'GET /api/mobile/recordings': (_) => jsonResponse(_body),
        'POST /api/mobile/recording': (_) => jsonResponse({'recording': true, 'id': 'x'}),
      }));
      await r.refresh();
      await r.start(lineKey: line, peer: '+49171');
      var notified = 0;
      r.addListener(() => notified++);
      r.retainLines({line});
      expect(notified, 0, reason: 'nothing changed');
      r.retainLines(const {});
      expect(r.recordingSince(line), isNull);
      expect(notified, 1);

      r.clear();
      expect(r.recordings, isEmpty);
      expect(r.isAllowed, isFalse);
      expect(r.hasLoaded, isFalse);
    });
  });
}
