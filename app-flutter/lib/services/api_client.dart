import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/directory.dart';
import '../models/extension_status.dart';
import '../models/forwarding.dart';
import '../models/pbx_call.dart';
import '../models/presence.dart';
import '../models/recording.dart';
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

  /// 403 on a feature the admin has not enabled for this extension (call recording).
  notAllowed,
}

/// First HA-Phone version with the presence and voicemail endpoints.
const kMinPbxVersionPhase3 = '0.7.107';

/// First HA-Phone version with the forwarding and call-history endpoints.
const kMinPbxVersionPhase5 = '0.7.110';

/// First HA-Phone version with call recording and call flip (*55).
const kMinPbxVersionPhase6 = '0.7.114';

/// Error with a German message that tells the user what to do.
class ApiException implements Exception {
  const ApiException(this.kind, [this.statusCode, this.minPbxVersion = kMinPbxVersionPhase3]);

  final ApiErrorKind kind;
  final int? statusCode;

  /// HA-Phone version the failed endpoint needs (for [ApiErrorKind.unsupported]).
  final String minPbxVersion;

  bool get needsRepairing => kind == ApiErrorKind.notPaired || kind == ApiErrorKind.unauthorized;

  String get message => switch (kind) {
        ApiErrorKind.notPaired => 'Gerät neu koppeln (QR-Code), damit Kontakte geladen werden.',
        ApiErrorKind.unauthorized => 'Gerät nicht mehr gekoppelt – Gerät neu koppeln (QR-Code).',
        ApiErrorKind.unreachable => 'Anlage nicht erreichbar – WLAN prüfen.',
        ApiErrorKind.server => 'Anlage meldet einen Fehler${statusCode != null ? ' (HTTP $statusCode)' : ''}.',
        ApiErrorKind.unsupported => 'Funktion braucht HA-Phone $minPbxVersion oder neuer.',
        ApiErrorKind.notAllowed => 'Für Ihre Nebenstelle nicht freigegeben – bitte beim Administrator nachfragen.',
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

  /// Own forwarding rules per presence status.
  Future<List<ForwardingRule>> fetchForwarding(DeviceAuth auth) async {
    final response = await _send(auth, 'GET', '/api/mobile/forwarding', minVersion: kMinPbxVersionPhase5);
    return parseForwardingRules(_decodeObject(response));
  }

  /// Replaces all own rules; returns what the PBX stored. 422 = invalid list.
  Future<List<ForwardingRule>> saveForwarding(DeviceAuth auth, List<ForwardingRule> rules) async {
    final response = await _send(
      auth,
      'PUT',
      '/api/mobile/forwarding',
      body: forwardingRulesToJson(rules),
      minVersion: kMinPbxVersionPhase5,
    );
    return parseForwardingRules(_decodeObject(response));
  }

  /// PBX call log of the own extension (all devices), newest first.
  Future<List<PbxCall>> fetchCalls(DeviceAuth auth, {int limit = 200}) async {
    final response = await _send(auth, 'GET', '/api/mobile/calls?limit=$limit', minVersion: kMinPbxVersionPhase5);
    return parsePbxCalls(_decodeObject(response));
  }

  /// Own call recordings plus whether recording is allowed, newest first.
  Future<RecordingList> fetchRecordings(DeviceAuth auth) async {
    final response = await _send(auth, 'GET', '/api/mobile/recordings', minVersion: kMinPbxVersionPhase6);
    return RecordingList.fromJson(_decodeObject(response));
  }

  /// Starts recording the own call with [peer] (MixMonitor on the PBX);
  /// returns the new recording's id. 403 = not allowed for this extension,
  /// 409 = no unique call found, 502 = PBX error.
  Future<String> startRecording(DeviceAuth auth, String peer) async {
    final response = await _controlRecording(auth, 'start', peer);
    return (_decodeObject(response)['id'] ?? '').toString();
  }

  /// Stops the recording of the own call with [peer]. 409 = none running.
  Future<void> stopRecording(DeviceAuth auth, String peer) async {
    await _controlRecording(auth, 'stop', peer);
  }

  Future<http.Response> _controlRecording(DeviceAuth auth, String action, String peer) => _send(
        auth,
        'POST',
        '/api/mobile/recording',
        body: {'action': action, 'peer': recordingPeer(peer)},
        minVersion: kMinPbxVersionPhase6,
        forbiddenIsNotAllowed: true,
      );

  /// URL of a recording's WAV file; needs [authHeaders].
  Uri recordingAudioUri(DeviceAuth auth, CallRecording recording) =>
      _uri(auth, '${_recordingPath(recording)}/audio');

  /// Downloads the WAV file (fallback when streaming with headers fails).
  Future<List<int>> downloadRecording(DeviceAuth auth, CallRecording recording) async {
    final response = await _send(
      auth,
      'GET',
      '${_recordingPath(recording)}/audio',
      notFoundIsUnsupported: false,
      timeout: _downloadTimeout,
    );
    return response.bodyBytes;
  }

  /// Deletes a recording. A 404 means it is already gone, which is fine.
  Future<void> deleteRecording(DeviceAuth auth, CallRecording recording) async {
    await _send(auth, 'DELETE', _recordingPath(recording), notFoundIsUnsupported: false, acceptNotFound: true);
  }

  /// "/api/mobile/recordings/<id>" (percent-encoded: ids may contain + * #).
  /// Malformed ids never reach the network.
  String _recordingPath(CallRecording recording) {
    if (!isValidRecordingId(recording.id)) throw const ApiException(ApiErrorKind.server);
    return '/api/mobile/recordings/${Uri.encodeComponent(recording.id)}';
  }

  Future<http.Response> _send(
    DeviceAuth auth,
    String method,
    String path, {
    Map<String, Object?>? body,
    bool notFoundIsUnsupported = true,
    bool acceptNotFound = false,
    Duration timeout = _timeout,
    String minVersion = kMinPbxVersionPhase3,
    bool forbiddenIsNotAllowed = false,
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
        'POST' => _client.post(uri, headers: headers, body: jsonEncode(body)),
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
    // Device auth fails with 401; a 403 there means "feature not enabled".
    if (status == 403 && forbiddenIsNotAllowed) throw ApiException(ApiErrorKind.notAllowed, status, minVersion);
    if (status == 401 || status == 403) throw ApiException(ApiErrorKind.unauthorized, status);
    if (status == 404 && acceptNotFound) return response;
    if (status == 404 && notFoundIsUnsupported) throw ApiException(ApiErrorKind.unsupported, 404, minVersion);
    if (status != 200) throw ApiException(ApiErrorKind.server, status);
    // PBX versions before an endpoint existed answer unknown /api paths with the
    // admin web app (HTML, 200) instead of a 404.
    final contentType = response.headers['content-type'] ?? '';
    if (notFoundIsUnsupported && contentType.contains('text/html')) {
      throw ApiException(ApiErrorKind.unsupported, 200, minVersion);
    }
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
