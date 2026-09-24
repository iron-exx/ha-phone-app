import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/presence.dart';
import 'package:ha_phone_test/models/voicemail.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/door_opener.dart';
import 'package:http/http.dart' as http;

import 'helpers/fake_api.dart';

final _msg = VoicemailMessage(id: 'INBOX/msg0003', isNew: true, receivedAt: DateTime(2026));

void main() {
  test('GET presence sends device headers and parses', () async {
    final pbx = FakePbx({
      'GET /api/mobile/presence': (_) => jsonResponse({
            'self': {'number': '12', 'presence': 'lunch', 'line': 'idle'},
            'extensions': [],
          }),
    });
    final s = await pbx.api.fetchPresence(testAuth);
    expect(s.self?.presence, Presence.lunch);
    final req = pbx.requests.single;
    expect(req.url.toString(), 'http://box/api/mobile/presence');
    expect(req.headers['X-Device-Id'], '1');
    expect(req.headers['X-Device-Token'], 't');
  });

  test('PUT presence sends the status as JSON', () async {
    final pbx = FakePbx({
      'PUT /api/mobile/presence': (req) => jsonResponse({'number': '12', 'presence': 'do_not_disturb'}),
    });
    final stored = await pbx.api.setPresence(testAuth, Presence.doNotDisturb);
    expect(stored, Presence.doNotDisturb);
    final req = pbx.requests.single;
    expect(jsonDecode(req.body), {'status': 'do_not_disturb'});
    expect(req.headers['Content-Type'], startsWith('application/json'));
  });

  Future<ApiException> errorOf(Future<Object?> Function() call) async {
    try {
      await call();
    } on ApiException catch (e) {
      return e;
    }
    fail('expected ApiException');
  }

  test('404 on the new endpoints asks for a newer HA-Phone', () async {
    final api = FakePbx({}).api;
    for (final call in [
      () => api.fetchPresence(testAuth),
      () => api.fetchVoicemail(testAuth),
      () => api.setPresence(testAuth, Presence.away),
    ]) {
      final e = await errorOf(call);
      expect(e.kind, ApiErrorKind.unsupported);
      expect(e.message, 'Funktion braucht HA-Phone 0.7.107 oder neuer.');
      expect(e.needsRepairing, isFalse);
    }
  });

  test('older PBX answering with its HTML admin page counts as too old', () async {
    http.Response html(http.Request _) => http.Response('<!DOCTYPE html><html></html>', 200, headers: {'content-type': 'text/html; charset=utf-8'});
    final api = FakePbx({'GET /api/mobile/presence': html, 'GET /api/mobile/voicemail': html}).api;
    for (final call in [() => api.fetchPresence(testAuth), () => api.fetchVoicemail(testAuth)]) {
      expect((await errorOf(call)).kind, ApiErrorKind.unsupported);
    }
  });

  test('422 and 401 on PUT presence', () async {
    final e422 = await errorOf(() =>
        FakePbx({'PUT /api/mobile/presence': (_) => http.Response('', 422)}).api.setPresence(testAuth, Presence.away));
    expect(e422.kind, ApiErrorKind.server);
    final e401 = await errorOf(() =>
        FakePbx({'PUT /api/mobile/presence': (_) => http.Response('', 401)}).api.setPresence(testAuth, Presence.away));
    expect(e401.needsRepairing, isTrue);
  });

  test('directory 404 stays a server error', () async {
    final e = await errorOf(() => FakePbx({}).api.fetchDirectory(testAuth));
    expect(e.kind, ApiErrorKind.server);
  });

  test('voicemail audio URL and delete path use folder and name', () async {
    final pbx = FakePbx({
      'DELETE /api/mobile/voicemail/INBOX/msg0003': (_) => jsonResponse({'success': true}),
      'GET /api/mobile/voicemail/INBOX/msg0003/audio': (_) => http.Response.bytes([1, 2, 3], 200),
    });
    expect(pbx.api.voicemailAudioUri(testAuth, _msg).toString(), 'http://box/api/mobile/voicemail/INBOX/msg0003/audio');
    expect(ApiClient.authHeaders(testAuth), {'X-Device-Id': '1', 'X-Device-Token': 't'});
    expect(await pbx.api.downloadVoicemail(testAuth, _msg), [1, 2, 3]);
    await pbx.api.deleteVoicemail(testAuth, _msg);
    expect(pbx.to('DELETE', '/api/mobile/voicemail/INBOX/msg0003'), hasLength(1));
  });

  test('voicemail audio 404: deleted elsewhere, not "HA-Phone too old"', () async {
    final e = await errorOf(() => FakePbx({}).api.downloadVoicemail(testAuth, _msg));
    expect(e.kind, ApiErrorKind.server);
    expect(e.message, 'Nicht mehr auf der Anlage – vermutlich woanders gelöscht.');
  });

  test('empty 2xx bodies are fine where the JSON is optional', () async {
    final pbx = FakePbx({
      'PUT /api/mobile/presence': (_) => http.Response('', 200),
      'POST /api/mobile/recording': (_) => http.Response('', 200),
      'PUT /api/mobile/forwarding': (_) => http.Response('', 204),
    });
    expect(await pbx.api.setPresence(testAuth, Presence.away), Presence.away);
    expect(await pbx.api.startRecording(testAuth, '16'), '');
    expect(await pbx.api.saveForwarding(testAuth, const []), isEmpty);
  });

  test('deleting an already deleted message (404) is fine', () async {
    await FakePbx({}).api.deleteVoicemail(testAuth, _msg);
  });

  test('malformed ids never reach the network', () async {
    final pbx = FakePbx({});
    final bad = VoicemailMessage(id: '../etc', isNew: false, receivedAt: DateTime(2026));
    expect((await errorOf(() => pbx.api.deleteVoicemail(testAuth, bad))).kind, ApiErrorKind.server);
    expect(pbx.requests, isEmpty);
  });

  group('POST door-open (webhook, 0.7.117)', () {
    test('sends the extension with device headers; 200 = opened', () async {
      final pbx = FakePbx({'POST /api/mobile/door-open': (_) => jsonResponse({'success': true})});
      expect(await pbx.api.openDoorRemote(testAuth, '16'), isTrue);
      final req = pbx.requests.single;
      expect(req.url.toString(), 'http://box/api/mobile/door-open');
      expect(jsonDecode(req.body), {'extension': '16'});
      expect(req.headers['X-Device-Id'], '1');
      expect(req.headers['X-Device-Token'], 't');
    });

    test('404 means no webhook for this door (fall back to DTMF)', () async {
      final pbx = FakePbx({'POST /api/mobile/door-open': (_) => http.Response('{"detail":"x"}', 404)});
      expect(await pbx.api.openDoorRemote(testAuth, '16'), isFalse);
    });

    test('401 asks for re-pairing, 502 is a server error', () async {
      var status = 401;
      final pbx = FakePbx({'POST /api/mobile/door-open': (_) => http.Response('{}', status)});
      expect((await errorOf(() => pbx.api.openDoorRemote(testAuth, '16'))).kind, ApiErrorKind.unauthorized);
      status = 502;
      expect((await errorOf(() => pbx.api.openDoorRemote(testAuth, '16'))).kind, ApiErrorKind.server);
    });

    test('an old PBX answering with HTML (200) means no webhook: fall back to DTMF', () async {
      final pbx = FakePbx({
        'POST /api/mobile/door-open': (_) => http.Response('<html></html>', 200, headers: {'content-type': 'text/html'}),
      });
      expect(await pbx.api.openDoorRemote(testAuth, '16'), isFalse);
      expect(await DoorOpener(api: pbx.api, authLoader: testAuthLoader).open('16'), DoorOpenResult.noWebhook);
    });

    test('non-numeric extensions never reach the network', () async {
      final pbx = FakePbx({});
      for (final bad in ['', '16/../x', 'abc', '1 6']) {
        expect((await errorOf(() => pbx.api.openDoorRemote(testAuth, bad))).kind, ApiErrorKind.server, reason: bad);
      }
      expect(pbx.requests, isEmpty);
    });

    test('DoorOpener maps the result', () async {
      var status = 200;
      final pbx = FakePbx({'POST /api/mobile/door-open': (_) => http.Response('{}', status)});
      final opener = DoorOpener(api: pbx.api, authLoader: testAuthLoader);
      expect(await opener.open('16'), DoorOpenResult.opened);
      status = 404;
      expect(await opener.open('16'), DoorOpenResult.noWebhook);
    });
  });
}
