import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/diagnostics_service.dart';
import 'package:ha_phone_test/utils/diagnostics_report.dart';

import 'helpers/fake_api.dart';

void main() {
  test('summary never contains the SIP password or the device token', () {
    final info = DiagnosticsInfo.fromNative(
      appVersion: '0.3.0',
      registration: 'Online (TLS)',
      credentials: {'host': '192.168.7.10', 'port': '5061', 'username': '13', 'password': 'geheim-sip-123'},
      deviceAuth: {'apiHost': '192.168.7.10', 'deviceId': 'dev-7', 'deviceToken': 'token-xyz-987'},
      reachability: const Reachability.ok(23),
      features: const [
        FeatureCheck('Präsenz', FeatureSupport.supported),
        FeatureCheck('Weiterleitungen', FeatureSupport.unsupported, minVersion: '0.7.110'),
      ],
    );
    final text = info.toText(now: DateTime(2026, 9, 23, 12));

    expect(text, isNot(contains('geheim-sip-123')));
    expect(text, isNot(contains('token-xyz-987')));
    expect(text, contains('SIP-Server: 192.168.7.10:5061 (TLS)'));
    expect(text, contains('Nebenstelle: 13'));
    expect(text, contains('API-Host: 192.168.7.10'));
    expect(text, contains('App-Version: 0.3.0'));
    expect(text, contains('Anlage: erreichbar · 23 ms'));
    expect(text, contains('Präsenz: ja'));
    expect(text, contains('Weiterleitungen: nein – Anlage zu alt (ab HA-Phone 0.7.110)'));
  });

  test('not paired: placeholders instead of empty values', () {
    final info = DiagnosticsInfo.fromNative(
      appVersion: '0.3.0',
      registration: 'Nicht verbunden',
      credentials: const {},
      deviceAuth: const {},
    );
    expect(info.sipServer, '–');
    expect(info.apiHost, contains('nicht per QR gekoppelt'));
    expect(info.toText(), contains('Anlage: nicht geprüft'));
  });

  test('probe: reachable, per-feature support from unsupported errors', () async {
    final fake = FakePbx({
      'GET /api/mobile/presence': (_) => jsonResponse({'self': {'number': '13'}, 'extensions': []}),
      'GET /api/mobile/voicemail': (_) => jsonResponse({'messages': [], 'new_count': 0}),
      // forwarding + calls missing -> 404 -> older PBX
    });
    final probe = await DiagnosticsService(api: fake.api, authLoader: testAuthLoader).probe();

    expect(probe.reachability.millis, isNotNull);
    expect(probe.reachability.text, startsWith('erreichbar · '));
    expect(probe.features.map((f) => f.support), [
      FeatureSupport.supported,
      FeatureSupport.supported,
      FeatureSupport.unsupported,
      FeatureSupport.unsupported,
    ]);
    expect(fake.to('GET', '/api/mobile/calls').single.url.queryParameters['limit'], '1');
  });

  test('probe: not paired is reported as the error kind', () async {
    final probe = await DiagnosticsService(
      api: FakePbx({}).api,
      authLoader: () async => const DeviceAuth(apiHost: '', deviceId: '', deviceToken: ''),
    ).probe();
    expect(probe.reachability.error?.kind, ApiErrorKind.notPaired);
    expect(probe.features, isEmpty);
  });
}
