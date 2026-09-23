import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/directory.dart';
import '../models/extension_status.dart';
import '../models/presence.dart';
import '../models/voicemail.dart';

enum ApiErrorKind {
  /// No device token stored (paired before 0.2.0, or manual setup).
  notPaired,

  /// 401/403: token revoked or device removed in the PBX admin.
  unauthorized,

  /// Network down, wrong WLAN, PBX off.
  unreachable,

  /// Unexpected status or malformed body.
  server,

  /// 404 on a newer endpoint: the PBX runs an older HA-Phone version.
  unsupported,
}

/// First HA-Phone version with the presence and voicemail endpoints.
const kMinPbxVersionPhase3 = '0.7.107';

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
        ApiErrorKind.unsupported => 'Funktion braucht HA-Phone $kMinPbxVersionPhase3 oder neuer.',
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
  static const _downloadTimeout = Duration(seconds: 30);

  /// Headers every /api/mobile/* request needs (also for the audio player).
  static Map<String, String> authHeaders(DeviceAuth auth) =>
      {'X-Device-Id': auth.deviceId, 'X-Device-Token': auth.deviceToken};

  Uri _uri(DeviceAuth auth, String path) => Uri.parse('http://${auth.apiHost}$path');

  Future<Directory> fetchDirectory(DeviceAuth auth) async {
    // 404 stays a server error here: the directory exists since 0.7.102.
    final response = await _send(auth, 'GET', '/api/mobile/directory', notFoundIsUnsupported: false);
    return Directory.fromJson(_decodeObject(response));
  }

  Future<PresenceSnapshot> fetchPresence(DeviceAuth auth) async {
    final response = await _send(auth, 'GET', '/api/mobile/presence');
    return PresenceSnapshot.fromJson(_decodeObject(response));
  }

  /// Sets the own presence; returns the value the PBX stored.
  Future<Presence> setPresence(DeviceAuth auth, Presence presence) async {
    final response = await _send(auth, 'PUT', '/api/mobile/presence', body: {'status': presence.apiValue});
    final stored = Presence.fromApi(_decodeObject(response)['presence'] as String?);
    return stored == Presence.unknown ? presence : stored;
  }

  Future<VoicemailBox> fetchVoicemail(DeviceAuth auth) async {
    final response = await _send(auth, 'GET', '/api/mobile/voicemail');
    return VoicemailBox.fromJson(_decodeObject(response));
  }

  /// URL of the WAV file; needs [authHeaders].
  Uri voicemailAudioUri(DeviceAuth auth, VoicemailMessage message) {
    final path = message.path;
    if (path == null) throw const ApiException(ApiErrorKind.server);
    return _uri(auth, '/api/mobile/voicemail/${path.folder}/${path.name}/audio');
  }

  /// Downloads the WAV file (fallback when streaming with headers fails).
  Future<List<int>> downloadVoicemail(DeviceAuth auth, VoicemailMessage message) async {
    final path = message.path;
    if (path == null) throw const ApiException(ApiErrorKind.server);
    final response = await _send(
      auth,
      'GET',
      '/api/mobile/voicemail/${path.folder}/${path.name}/audio',
      timeout: _downloadTimeout,
    );
    return response.bodyBytes;
  }

  /// Deletes a message. A 404 means it is already gone, which is fine.
  Future<void> deleteVoicemail(DeviceAuth auth, VoicemailMessage message) async {
    final path = message.path;
    if (path == null) throw const ApiException(ApiErrorKind.server);
    await _send(
      auth,
      'DELETE',
      '/api/mobile/voicemail/${path.folder}/${path.name}',
      notFoundIsUnsupported: false,
      acceptNotFound: true,
    );
  }

  Future<http.Response> _send(
    DeviceAuth auth,
    String method,
    String path, {
    Map<String, Object?>? body,
    bool notFoundIsUnsupported = true,
    bool acceptNotFound = false,
    Duration timeout = _timeout,
  }) async {
    if (!auth.isComplete) throw const ApiException(ApiErrorKind.notPaired);
    final uri = _uri(auth, path);
    final headers = {
      ...authHeaders(auth),
      if (body != null) 'Content-Type': 'application/json',
    };
    final http.Response response;
    try {
      final Future<http.Response> request = switch (method) {
        'PUT' => _client.put(uri, headers: headers, body: jsonEncode(body)),
        'DELETE' => _client.delete(uri, headers: headers),
        _ => _client.get(uri, headers: headers),
      };
      response = await request.timeout(timeout);
    } on SocketException {
      throw const ApiException(ApiErrorKind.unreachable);
    } on TimeoutException {
      throw const ApiException(ApiErrorKind.unreachable);
    } on http.ClientException {
      throw const ApiException(ApiErrorKind.unreachable);
    }
    final status = response.statusCode;
    if (status == 401 || status == 403) throw ApiException(ApiErrorKind.unauthorized, status);
    if (status == 404 && acceptNotFound) return response;
    if (status == 404 && notFoundIsUnsupported) throw const ApiException(ApiErrorKind.unsupported, 404);
    if (status != 200) throw ApiException(ApiErrorKind.server, status);
    return response;
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) throw const FormatException('not an object');
      return body;
    } on FormatException {
      throw const ApiException(ApiErrorKind.server);
    }
  }
}
