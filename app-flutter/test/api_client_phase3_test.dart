import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/presence.dart';
import 'package:ha_phone_test/models/voicemail.dart';
import 'package:ha_phone_test/services/api_client.dart';
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

  test('deleting an already deleted message (404) is fine', () async {
    await FakePbx({}).api.deleteVoicemail(testAuth, _msg);
  });

  test('malformed ids never reach the network', () async {
    final pbx = FakePbx({});
    final bad = VoicemailMessage(id: '../etc', isNew: false, receivedAt: DateTime(2026));
    expect((await errorOf(() => pbx.api.deleteVoicemail(testAuth, bad))).kind, ApiErrorKind.server);
    expect(pbx.requests, isEmpty);
  });
}
