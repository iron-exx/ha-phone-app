import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/local_store.dart';
import 'package:ha_phone_test/services/voicemail_repository.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_api.dart';

final _body = {
  'messages': [
    {'id': 'INBOX/msg0000', 'new': true, 'caller_number': '11', 'duration_sec': 3, 'received_at': 1790000000},
    {'id': 'INBOX/msg0001', 'new': true, 'caller_number': '12', 'duration_sec': 4, 'received_at': 1790000100},
    {'id': 'Old/msg0000', 'new': false, 'caller_number': '13', 'duration_sec': 5, 'received_at': 1780000000},
  ],
  'new_count': 2,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  VoicemailRepository repo(FakePbx pbx) => VoicemailRepository(
        api: pbx.api,
        authLoader: testAuthLoader,
        pollInterval: const Duration(hours: 1),
      );

  test('badge counts new messages and clears when heard locally', () async {
    final r = repo(FakePbx({'GET /api/mobile/voicemail': (_) => jsonResponse(_body)}));
    await r.refresh();
    expect(r.messages, hasLength(3));
    expect(r.unheardCount, 2);

    await r.markHeard(r.messages.first);
    expect(r.unheardCount, 1);
    expect(r.isUnheard(r.messages.first), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(StoreKeys.voicemailHeard), ['INBOX/msg0001@1790000100']);
  });

  test('heard ids survive a restart and stale ones are pruned', () async {
    SharedPreferences.setMockInitialValues({
      StoreKeys.voicemailHeard: ['INBOX/msg0000@1790000000', 'INBOX/msg0009@1'],
    });
    final r = repo(FakePbx({'GET /api/mobile/voicemail': (_) => jsonResponse(_body)}));
    await r.refresh();
    expect(r.unheardCount, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(StoreKeys.voicemailHeard), ['INBOX/msg0000@1790000000']);
  });

  test('delete removes the message after the PBX confirmed', () async {
    final pbx = FakePbx({
      'GET /api/mobile/voicemail': (_) => jsonResponse(_body),
      'DELETE /api/mobile/voicemail/INBOX/msg0001': (_) => jsonResponse({'success': true}),
    });
    final r = repo(pbx);
    await r.refresh();
    await r.delete(r.messages.first);
    expect(r.messages.map((m) => m.id), ['INBOX/msg0000', 'Old/msg0000']);
    expect(r.unheardCount, 1);
  });

  test('failed delete keeps the message', () async {
    final r = repo(FakePbx({
      'GET /api/mobile/voicemail': (_) => jsonResponse(_body),
      'DELETE /api/mobile/voicemail/INBOX/msg0001': (_) => http.Response('', 500),
    }));
    await r.refresh();
    await expectLater(r.delete(r.messages.first), throwsA(isA<ApiException>()));
    expect(r.messages, hasLength(3));
  });

  test('older PBX: unsupported, no crash, no messages', () async {
    final r = repo(FakePbx({}));
    await r.refresh();
    expect(r.isUnsupported, isTrue);
    expect(r.messages, isEmpty);
    expect(r.unheardCount, 0);
  });
}
