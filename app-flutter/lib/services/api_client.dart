import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/directory.dart';

enum ApiErrorKind {
  /// No device token stored (paired before 0.2.0, or manual setup).
  notPaired,

  /// 401/403: token revoked or device removed in the PBX admin.
  unauthorized,

  /// Network down, wrong WLAN, PBX off.
  unreachable,

  /// Unexpected status or malformed body.
  server,
}

/// Error with a German message that tells the user what to do.
class ApiException implements Exception {
  const ApiException(this.kind, [this.statusCode]);

  final ApiErrorKind kind;
  final int? statusCode;

  bool get needsRepairing => kind == ApiErrorKind.notPaired || kind == ApiErrorKind.unauthorized;

  String get message => switch (kind) {
        ApiErrorKind.notPaired => 'Gerät neu koppeln (QR-Code), damit Kontakte geladen werden.',
        ApiErrorKind.unauthorized => 'Gerät nicht mehr gekoppelt – Gerät neu koppeln (QR-Code).',
        ApiErrorKind.unreachable => 'Anlage nicht erreichbar – WLAN prüfen.',
        ApiErrorKind.server => 'Anlage meldet einen Fehler${statusCode != null ? ' (HTTP $statusCode)' : ''}.',
      };

  @override
  String toString() => 'ApiException($kind, $statusCode)';
}

/// Credentials for the /api/mobile/* endpoints, from SipChannel.getDeviceAuth.
class DeviceAuth {
  const DeviceAuth({required this.apiHost, required this.deviceId, required this.deviceToken});

  factory DeviceAuth.fromMap(Map<String, String> m) => DeviceAuth(
        apiHost: m['apiHost'] ?? '',
        deviceId: m['deviceId'] ?? '',
        deviceToken: m['deviceToken'] ?? '',
      );

  final String apiHost;
  final String deviceId;
  final String deviceToken;

  bool get isComplete => apiHost.isNotEmpty && deviceId.isNotEmpty && deviceToken.isNotEmpty;
}

/// Plain-HTTP client for the HA-Phone mobile API (port 80 on the box, LAN only).
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 8);

  Future<Directory> fetchDirectory(DeviceAuth auth) async {
    if (!auth.isComplete) throw const ApiException(ApiErrorKind.notPaired);
    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse('http://${auth.apiHost}/api/mobile/directory'),
        headers: {'X-Device-Id': auth.deviceId, 'X-Device-Token': auth.deviceToken},
      ).timeout(_timeout);
    } on SocketException {
      throw const ApiException(ApiErrorKind.unreachable);
    } on TimeoutException {
      throw const ApiException(ApiErrorKind.unreachable);
    } on http.ClientException {
      throw const ApiException(ApiErrorKind.unreachable);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(ApiErrorKind.unauthorized, response.statusCode);
    }
    if (response.statusCode != 200) {
      throw ApiException(ApiErrorKind.server, response.statusCode);
    }
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) throw const FormatException('not an object');
      return Directory.fromJson(body);
    } on FormatException {
      throw const ApiException(ApiErrorKind.server);
    }
  }
}
