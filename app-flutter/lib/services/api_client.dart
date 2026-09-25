import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/doorbell_event.dart';
import '../models/directory.dart';
import '../models/extension_status.dart';
import '../models/forwarding.dart';
import '../models/pbx_call.dart';
import '../models/presence.dart';
import '../models/recording.dart';
import '../models/voicemail.dart';
import 'pbx_tls.dart';

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

  /// TLS handshake failed: the box presents a different cert than the paired one.
  certificateMismatch,
}

/// First HA-Phone version with the presence and voicemail endpoints.
const kMinPbxVersionPhase3 = '0.7.107';

/// First HA-Phone version with the forwarding and call-history endpoints.
const kMinPbxVersionPhase5 = '0.7.110';

/// First HA-Phone version with call recording and call flip (*55).
const kMinPbxVersionPhase6 = '0.7.114';

/// First HA-Phone version with the door-open webhook (POST /api/mobile/door-open).
const kMinPbxVersionDoorOpen = '0.7.117';

/// First HA-Phone version with POST /api/mobile/test-call.
const kMinPbxVersionTestCall = '0.7.118';

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
        // 404 on an item that existed (message deleted on the desk phone or in the admin UI).
        ApiErrorKind.server when statusCode == 404 => 'Nicht mehr auf der Anlage – vermutlich woanders gelöscht.',
        ApiErrorKind.server => 'Anlage meldet einen Fehler${statusCode != null ? ' (HTTP $statusCode)' : ''}.',
        ApiErrorKind.unsupported => 'Funktion braucht HA-Phone $minPbxVersion oder neuer.',
        ApiErrorKind.notAllowed => 'Für deine Nebenstelle nicht freigegeben – bitte beim Administrator nachfragen.',
        ApiErrorKind.certificateMismatch =>
          'Sichere Verbindung abgelehnt: Die Anlage hat ein anderes Zertifikat. Gerät neu koppeln (QR-Code).',
      };

  @override
  String toString() => 'ApiException($kind, $statusCode)';
}

/// Credentials for the /api/mobile/* endpoints, from SipChannel.getDeviceAuth.
class DeviceAuth {
  const DeviceAuth({
    required this.apiHost,
    required this.deviceId,
    required this.deviceToken,
    this.tlsPin = '',
    this.httpsPort = 0,
  });

  factory DeviceAuth.fromMap(Map<String, String> m) => DeviceAuth(
        apiHost: m['apiHost'] ?? '',
        deviceId: m['deviceId'] ?? '',
        deviceToken: m['deviceToken'] ?? '',
        tlsPin: m['tlsPin'] ?? '',
        httpsPort: int.tryParse(m['httpsPort'] ?? '') ?? 0,
      );

  final String apiHost;
  final String deviceId;
  final String deviceToken;

  /// SHA-256 of the box's TLS cert and its HTTPS port (HA-Phone 0.7.130+), see pbx_tls.dart.
  final String tlsPin;
  final int httpsPort;

  bool get isComplete => apiHost.isNotEmpty && deviceId.isNotEmpty && deviceToken.isNotEmpty;

  bool get isPinned => httpsPort > 0 && isValidPin(tlsPin);

  /// "https://host:8443" when pinned, else "http://<apiHost>" like before 0.7.130.
  Uri get baseUri {
    if (!isPinned) return Uri.parse('http://$apiHost');
    return Uri(scheme: 'https', host: _hostOnly(apiHost), port: httpsPort);
  }

  static String _hostOnly(String h) {
    final t = h.trim();
    if (t.startsWith('[')) return t.substring(1, t.indexOf(']'));
    return ':'.allMatches(t).length == 1 ? t.substring(0, t.indexOf(':')) : t;
  }
}

/// Client for the HA-Phone mobile API: pinned HTTPS (8443) when the pairing has a
/// cert fingerprint, else plain HTTP on port 80 like before HA-Phone 0.7.130.
class ApiClient {
  ApiClient({http.Client? client}) : _injected = client;

  /// Test seam: used for every request, pinned or not.
  final http.Client? _injected;
  static final http.Client _plain = http.Client();

  http.Client _clientFor(DeviceAuth auth) =>
      _injected ?? (auth.isPinned ? PinnedClients.forPin(auth.tlsPin) : _plain);

  static const _timeout = Duration(seconds: 8);
  static const _downloadTimeout = Duration(seconds: 30);

  /// Headers every /api/mobile/* request needs (also for the audio player).
  static Map<String, String> authHeaders(DeviceAuth auth) =>
      {'X-Device-Id': auth.deviceId, 'X-Device-Token': auth.deviceToken};

  Uri _uri(DeviceAuth auth, String path) => Uri.parse('${auth.baseUri}$path');

  /// Cert pin of the box for a device paired before HA-Phone 0.7.130 (trust on first use,
  /// the device token already proves it is our box); null when the PBX has none.
  Future<({String fingerprint, int httpsPort})?> fetchTlsPin(DeviceAuth auth) async {
    final response = await _send(auth, 'GET', '/api/mobile/config', notFoundIsUnsupported: false);
    final body = _decodeObject(response);
    final fp = body['tls_fingerprint'] as String? ?? '';
    final port = (body['api_https_port'] as num?)?.toInt() ?? 0;
    return isValidPin(fp) && port > 0 ? (fingerprint: normalizePin(fp), httpsPort: port) : null;
  }

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
    final stored = Presence.fromApi(_decodeOptionalObject(response)['presence'] as String?);
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
  /// 404: the message was deleted elsewhere (the endpoint exists, the list had it).
  Future<List<int>> downloadVoicemail(DeviceAuth auth, VoicemailMessage message) async {
    final path = message.path;
    if (path == null) throw const ApiException(ApiErrorKind.server);
    final response = await _send(
      auth,
      'GET',
      '/api/mobile/voicemail/${path.folder}/${path.name}/audio',
      notFoundIsUnsupported: false,
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
    // An empty 2xx body means "stored as sent".
    if (response.bodyBytes.isEmpty) return rules;
    return parseForwardingRules(_decodeObject(response));
  }

  /// PBX call log of the own extension (all devices), newest first.
  /// Rings at door stations, newest first. 404 = PBX older than 0.7.126 (unsupported).
  Future<List<DoorbellEvent>> fetchDoorbell(DeviceAuth auth, {int limit = 30}) async {
    final response = await _send(auth, 'GET', '/api/mobile/doorbell?limit=$limit');
    try {
      return parseDoorbellEvents(jsonDecode(utf8.decode(response.bodyBytes)));
    } on FormatException {
      throw const ApiException(ApiErrorKind.server);
    }
  }

  Future<List<int>> downloadDoorbellImage(DeviceAuth auth, int eventId) async {
    final response = await _send(auth, 'GET', '/api/mobile/doorbell/$eventId/image',
        notFoundIsUnsupported: false, timeout: _downloadTimeout);
    return response.bodyBytes;
  }

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
    return (_decodeOptionalObject(response)['id'] ?? '').toString();
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

  /// Asks the PBX to ring this device after [delaySec] ("Test-Anruf an mich"). Throws
  /// [ApiException] (status 429 when a test ran less than a minute ago).
  Future<void> requestTestCall(DeviceAuth auth, {int delaySec = 10}) async {
    await _send(auth, 'POST', '/api/mobile/test-call', body: {'delay_sec': delaySec}, minVersion: kMinPbxVersionTestCall);
  }

  /// Opens door station [extension] through its webhook on the PBX (no call
  /// needed). Returns false on 404 or on the admin web app's HTML page (200):
  /// the door has no webhook configured or the PBX predates 0.7.117, so the
  /// caller falls back to the DTMF code.
  Future<bool> openDoorRemote(DeviceAuth auth, String extension) async {
    // The PBX only knows numeric extensions; anything else never leaves the app.
    if (!RegExp(r'^\d{1,10}$').hasMatch(extension)) throw const ApiException(ApiErrorKind.server);
    final response = await _send(
      auth,
      'POST',
      '/api/mobile/door-open',
      body: {'extension': extension},
      notFoundIsUnsupported: false,
      acceptNotFound: true,
      minVersion: kMinPbxVersionDoorOpen,
    );
    if (response.statusCode == 404) return false;
    return !(response.headers['content-type'] ?? '').contains('text/html');
  }

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
    final client = _clientFor(auth);
    try {
      final Future<http.Response> request = switch (method) {
        'PUT' => client.put(uri, headers: headers, body: jsonEncode(body)),
        'POST' => client.post(uri, headers: headers, body: jsonEncode(body)),
        'DELETE' => client.delete(uri, headers: headers),
        _ => client.get(uri, headers: headers),
      };
      response = await request.timeout(timeout);
    } on HandshakeException {
      throw const ApiException(ApiErrorKind.certificateMismatch);
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
    if (status < 200 || status >= 300) throw ApiException(ApiErrorKind.server, status);
    // PBX versions before an endpoint existed answer unknown /api paths with the
    // admin web app (HTML, 200) instead of a 404.
    final contentType = response.headers['content-type'] ?? '';
    if (notFoundIsUnsupported && contentType.contains('text/html')) {
      throw ApiException(ApiErrorKind.unsupported, 200, minVersion);
    }
    return response;
  }

  /// Like [_decodeObject], but an empty 2xx body (a PBX that only answers
  /// with a status) is an empty object instead of an error.
  Map<String, dynamic> _decodeOptionalObject(http.Response response) =>
      response.bodyBytes.isEmpty ? const {} : _decodeObject(response);

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
