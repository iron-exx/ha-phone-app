import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _auth = DeviceAuth(apiHost: '192.168.7.10', deviceId: '4', deviceToken: 'tok');

void main() {
  test('sends device headers and parses the directory', () async {
    late http.Request seen;
    final api = ApiClient(
      client: MockClient((req) async {
        seen = req;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'self': {'number': '13', 'name': 'Test', 'presence': 'away'},
            'extensions': [
              {'number': '16', 'name': 'türklingel', 'video': true, 'door_open_code': '*1'},
            ],
            'phonebook': [],
          })),
          200,
        );
      }),
    );
    final d = await api.fetchDirectory(_auth);
    expect(seen.url.toString(), 'http://192.168.7.10/api/mobile/directory');
    expect(seen.headers['X-Device-Id'], '4');
    expect(seen.headers['X-Device-Token'], 'tok');
    expect(d.extensions.single.name, 'türklingel');
    expect(d.self?.name, 'Test');
  });

  Future<ApiException> errorFor(MockClient client, [DeviceAuth auth = _auth]) async {
    try {
      await ApiClient(client: client).fetchDirectory(auth);
    } on ApiException catch (e) {
      return e;
    }
    fail('expected ApiException');
  }

  test('401 asks to re-pair', () async {
    final e = await errorFor(MockClient((_) async => http.Response('', 401)));
    expect(e.kind, ApiErrorKind.unauthorized);
    expect(e.needsRepairing, isTrue);
    expect(e.message, contains('Gerät neu koppeln'));
  });

  test('missing device token asks to re-pair without a request', () async {
    var requested = false;
    final e = await errorFor(
      MockClient((_) async {
        requested = true;
        return http.Response('', 200);
      }),
      const DeviceAuth(apiHost: '', deviceId: '', deviceToken: ''),
    );
    expect(e.kind, ApiErrorKind.notPaired);
    expect(requested, isFalse);
  });

  test('network errors say to check the WLAN', () async {
    final e = await errorFor(MockClient((_) async => throw const SocketException('down')));
    expect(e.kind, ApiErrorKind.unreachable);
    expect(e.message, 'Anlage nicht erreichbar – WLAN prüfen.');
  });

  test('server errors and bad bodies are reported', () async {
    expect((await errorFor(MockClient((_) async => http.Response('', 500)))).message, contains('500'));
    expect((await errorFor(MockClient((_) async => http.Response('nope', 200)))).kind, ApiErrorKind.server);
  });
}
