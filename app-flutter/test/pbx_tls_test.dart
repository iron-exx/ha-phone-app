import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/pbx_tls.dart';
import 'package:ha_phone_test/utils/diagnostics_report.dart';
import 'package:http/http.dart' as http;

import 'helpers/fake_api.dart';

final _pin = 'ab' * 32;

void main() {
  group('DeviceAuth base URL', () {
    test('plain http without a pin (PBX before 0.7.130)', () {
      final a = DeviceAuth.fromMap({'apiHost': '192.168.7.10', 'deviceId': '1', 'deviceToken': 't'});
      expect(a.isPinned, isFalse);
      expect(a.baseUri.toString(), 'http://192.168.7.10');
    });

    test('https on the pinned port, any http port dropped', () {
      final a = DeviceAuth.fromMap({
        'apiHost': '100.117.178.114:80',
        'deviceId': '1',
        'deviceToken': 't',
        'tlsPin': _pin,
        'httpsPort': '8443',
      });
      expect(a.isPinned, isTrue);
      expect(a.baseUri.toString(), 'https://100.117.178.114:8443');
    });

    test('a broken pin or missing port stays on http', () {
      final a = DeviceAuth.fromMap({'apiHost': 'box', 'deviceId': '1', 'deviceToken': 't', 'tlsPin': 'nothex', 'httpsPort': '8443'});
      final b = DeviceAuth.fromMap({'apiHost': 'box', 'deviceId': '1', 'deviceToken': 't', 'tlsPin': _pin, 'httpsPort': '0'});
      expect(a.isPinned, isFalse);
      expect(b.isPinned, isFalse);
    });
  });

  test('certificate check compares the SHA-256 of the DER bytes', () {
    final der = utf8.encode('abc');
    final fp = sha256.convert(der).toString();
    expect(certMatchesPin(der, fp), isTrue);
    expect(certMatchesPin(der, fp.toUpperCase()), isTrue);
    expect(certMatchesPin(der, _pin), isFalse);
    expect(certMatchesPin(der, ''), isFalse);
  });

  test('pinned auth sends API calls to https://host:8443', () async {
    final fake = FakePbx({
      'GET /api/mobile/presence': (_) => jsonResponse({'self': {'number': '18', 'presence': 'available'}, 'extensions': []}),
    });
    const auth = DeviceAuth(apiHost: 'box', deviceId: '1', deviceToken: 't', tlsPin: 'cd', httpsPort: 8443);
    final pinned = DeviceAuth(apiHost: 'box', deviceId: '1', deviceToken: 't', tlsPin: 'cd' * 32, httpsPort: 8443);
    await fake.api.fetchPresence(pinned);
    await fake.api.fetchPresence(auth);
    expect(fake.requests.first.url.toString(), 'https://box:8443/api/mobile/presence');
    expect(fake.requests.last.url.scheme, 'http');
  });

  test('fetchTlsPin reads fingerprint and port from /api/mobile/config', () async {
    final fake = FakePbx({
      'GET /api/mobile/config': (_) => jsonResponse({'extension_number': 18, 'tls_fingerprint': _pin, 'api_https_port': 8443}),
    });
    final pin = await fake.api.fetchTlsPin(testAuth);
    expect(pin, (fingerprint: _pin, httpsPort: 8443));

    final old = FakePbx({'GET /api/mobile/config': (_) => jsonResponse({'extension_number': 18})});
    expect(await old.api.fetchTlsPin(testAuth), isNull);
  });

  test('Diagnose names the connection security', () {
    expect(apiSecurityText(const DeviceAuth(apiHost: '', deviceId: '', deviceToken: '')), '–');
    expect(apiSecurityText(testAuth), 'HTTP, unverschlüsselt (Anlage vor 0.7.130)');
    expect(
      apiSecurityText(DeviceAuth(apiHost: 'box', deviceId: '1', deviceToken: 't', tlsPin: _pin, httpsPort: 8443)),
      'HTTPS · Zertifikat geprüft (abababababab…)',
    );
  });

  test('a TLS handshake failure (wrong cert) is its own error kind', () async {
    final api = ApiClient(client: _Throwing());
    const auth = DeviceAuth(apiHost: 'box', deviceId: '1', deviceToken: 't');
    expect(
      () => api.fetchPresence(auth),
      throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.certificateMismatch)),
    );
  });
}

class _Throwing extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw const HandshakeException('CERTIFICATE_VERIFY_FAILED');
}
