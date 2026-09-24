import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/ring_settings.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/call_history_store.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/favorites_store.dart';
import 'package:ha_phone_test/services/forwarding_repository.dart';
import 'package:ha_phone_test/services/pairing_reset.dart';
import 'package:ha_phone_test/services/presence_repository.dart';
import 'package:ha_phone_test/services/recordings_repository.dart';
import 'package:ha_phone_test/services/ring_settings_repository.dart';
import 'package:ha_phone_test/services/voicemail_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_api.dart';
import 'helpers/fake_sip.dart';

Map<String, Object?> _directory() => {
      'self': {'number': '18', 'name': 'Ich'},
      'extensions': [
        {'number': '16', 'name': 'Tür', 'door_open_code': '*1', 'door_open_remote': true},
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeSip sip;

  setUp(() {
    SharedPreferences.setMockInitialValues({'favorites_v1': ['11']});
    sip = FakeSip({'setRingPolicy': (args) => args})..install();
  });
  tearDown(() => sip.uninstall());

  test('clears repositories, favourites, ring policy and the native copies', () async {
    final pbx = FakePbx({'GET /api/mobile/directory': (_) => jsonResponse(_directory())});
    final dir = DirectoryRepository(api: pbx.api, authLoader: testAuthLoader);
    await dir.refresh();
    expect(dir.directory, isNotNull);
    await FavoritesStore.instance.load();
    expect(FavoritesStore.instance.numbers, {'11'});
    final ring = RingSettingsRepository();
    await ring.update(RingSettings(mutedUntil: DateTime.now().add(const Duration(hours: 1))));
    sip.calls.clear();

    await resetForPairing(
      directory: dir,
      presence: PresenceRepository(api: pbx.api, authLoader: testAuthLoader),
      forwarding: ForwardingRepository(api: pbx.api, authLoader: testAuthLoader),
      history: CallHistoryStore(api: pbx.api, authLoader: testAuthLoader),
      voicemail: VoicemailRepository(api: pbx.api, authLoader: testAuthLoader),
      recordings: RecordingsRepository(api: pbx.api, authLoader: testAuthLoader),
      ring: ring,
    );

    expect(dir.directory, isNull);
    expect(FavoritesStore.instance.numbers, isEmpty);
    expect((await SharedPreferences.getInstance()).getStringList('favorites_v1'), isNull);
    expect(ring.settings.mutedUntil, isNull);
    expect(sip.callsTo('setDoorCodes').single.arguments, isEmpty);
    expect(sip.callsTo('setDoorActions').single.arguments, isEmpty);
    expect(sip.callsTo('setDoorOpenRemote').single.arguments, isEmpty);
    expect(sip.callsTo('setCarDirectory').single.arguments, {'entries': [], 'self': ''});
    expect(sip.callsTo('setFavorites').single.arguments, isEmpty);
    expect(sip.callsTo('setRingPolicy'), hasLength(1));
    ring.dispose();
  });

  test('a directory refresh in flight during clear() does not bring the old box back', () async {
    final slow = Completer<http.Response>();
    final dir = DirectoryRepository(
      api: ApiClient(client: MockClient((_) => slow.future)),
      authLoader: testAuthLoader,
    );
    final refresh = dir.refresh();
    await pumpEventQueue();
    await dir.clear();
    slow.complete(jsonResponse(_directory()));
    await refresh;
    expect(dir.directory, isNull);
    expect(sip.callsTo('setDoorCodes'), isEmpty, reason: 'old door codes not pushed to native');
  });
}
