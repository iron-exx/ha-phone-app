import 'dart:convert';

import 'package:ha_phone_test/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const testAuth = DeviceAuth(apiHost: 'box', deviceId: '1', deviceToken: 't');

Future<DeviceAuth> testAuthLoader() async => testAuth;

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

/// Fake PBX: routes "METHOD /path" to a handler and records every request.
class FakePbx {
  FakePbx(this.routes);

  final Map<String, http.Response Function(http.Request request)> routes;
  final List<http.Request> requests = [];

  ApiClient get api => ApiClient(client: client);

  MockClient get client => MockClient((req) async {
        requests.add(req);
        final handler = routes['${req.method} ${req.url.path}'];
        return handler == null ? http.Response('', 404) : handler(req);
      });

  Iterable<http.Request> to(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path);
}
