import '../services/api_client.dart';

/// Whether the PBX offers an app feature (HA-Phone version check).
enum FeatureSupport {
  supported('ja'),
  unsupported('nein – Anlage zu alt'),
  unknown('unbekannt');

  const FeatureSupport(this.label);
  final String label;

  /// Success -> supported, 404/HTML -> unsupported, anything else unknown.
  static FeatureSupport fromError(ApiException? e) {
    if (e == null) return supported;
    return e.kind == ApiErrorKind.unsupported ? unsupported : unknown;
  }
}

class FeatureCheck {
  const FeatureCheck(this.label, this.support, {this.minVersion = '', this.error});

  final String label;
  final FeatureSupport support;

  /// HA-Phone version the feature needs, e.g. "0.7.110".
  final String minVersion;
  final ApiException? error;

  String get text => switch (support) {
        FeatureSupport.unsupported => '${support.label} (ab HA-Phone $minVersion)',
        FeatureSupport.unknown => '${support.label}${error != null ? ' – ${error!.message}' : ''}',
        FeatureSupport.supported => support.label,
      };
}

/// Result of the PBX reachability check (GET /api/mobile/presence).
class Reachability {
  const Reachability.ok(this.millis) : error = null;
  const Reachability.failed(ApiException this.error) : millis = null;

  final int? millis;
  final ApiException? error;

  String get text => millis != null ? 'erreichbar · $millis ms' : 'nicht erreichbar – ${error!.message}';
}

/// Everything the Diagnose screen shows. Built only from non-secret fields:
/// the SIP password and the device token never enter this class.
class DiagnosticsInfo {
  const DiagnosticsInfo({
    required this.appVersion,
    required this.registration,
    required this.sipServer,
    required this.sipUser,
    required this.transport,
    required this.apiHost,
    required this.deviceId,
    this.reachability,
    this.features = const [],
  });

  /// Picks the safe keys from SipChannel.getCredentials / getDeviceAuth.
  factory DiagnosticsInfo.fromNative({
    required String appVersion,
    required String registration,
    required Map<String, String> credentials,
    required Map<String, String> deviceAuth,
    Reachability? reachability,
    List<FeatureCheck> features = const [],
  }) {
    final host = credentials['host'] ?? '';
    final port = credentials['port'] ?? '';
    return DiagnosticsInfo(
      appVersion: appVersion,
      registration: registration,
      sipServer: host.isEmpty ? '–' : (port.isEmpty ? host : '$host:$port'),
      sipUser: (credentials['username'] ?? '').isEmpty ? '–' : credentials['username']!,
      // The app only registers over TLS (see HANDOFF).
      transport: 'TLS',
      apiHost: (deviceAuth['apiHost'] ?? '').isEmpty ? '– (nicht per QR gekoppelt)' : deviceAuth['apiHost']!,
      deviceId: (deviceAuth['deviceId'] ?? '').isEmpty ? '–' : deviceAuth['deviceId']!,
      reachability: reachability,
      features: features,
    );
  }

  final String appVersion;
  final String registration;
  final String sipServer;
  final String sipUser;
  final String transport;
  final String apiHost;
  final String deviceId;
  final Reachability? reachability;
  final List<FeatureCheck> features;

  DiagnosticsInfo copyWith({String? registration, Reachability? reachability, List<FeatureCheck>? features}) =>
      DiagnosticsInfo(
        appVersion: appVersion,
        registration: registration ?? this.registration,
        sipServer: sipServer,
        sipUser: sipUser,
        transport: transport,
        apiHost: apiHost,
        deviceId: deviceId,
        reachability: reachability ?? this.reachability,
        features: features ?? this.features,
      );

  /// Plain-text summary for "Diagnose kopieren".
  String toText({DateTime? now}) {
    final t = now ?? DateTime.now();
    return [
      'HA-Phone App – Diagnose (${t.toIso8601String().substring(0, 19)})',
      'App-Version: $appVersion',
      'Registrierung: $registration',
      'SIP-Server: $sipServer ($transport)',
      'Nebenstelle: $sipUser',
      'API-Host: $apiHost',
      'Geräte-ID: $deviceId',
      'Anlage: ${reachability?.text ?? 'nicht geprüft'}',
      for (final f in features) '${f.label}: ${f.text}',
    ].join('\n');
  }
}
