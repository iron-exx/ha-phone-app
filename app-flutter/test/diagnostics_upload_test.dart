import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ha_phone_test/services/api_client.dart';

const _auth = DeviceAuth(apiHost: 'pbx', deviceId: '1', deviceToken: 't');

void main() {
  test('uploads the log with version and note and returns the stored name', () async {
    late Map<String, dynamic> sent;
    final api = ApiClient(client: MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/api/mobile/diagnostics');
      expect(req.headers['X-Device-Token'], 't');
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'name': 'ext12-dev19-20260929-205002.log'}), 200,
          headers: {'content-type': 'application/json'});
    }));
    final name = await api.uploadDiagnostics(_auth, 'line 1\nline 2', appVersion: '1.7.3', note: 'Tür 20:50');
    expect(name, 'ext12-dev19-20260929-205002.log');
    expect(sent, {'log': 'line 1\nline 2', 'app_version': '1.7.3', 'note': 'Tür 20:50'});
  });

  test('an older PBX without the endpoint is reported as unsupported', () async {
    final api = ApiClient(client: MockClient((req) async => http.Response('', 404)));
    expect(
      () => api.uploadDiagnostics(_auth, 'x'),
      throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.unsupported)),
    );
  });
}
