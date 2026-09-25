import 'package:flutter/services.dart';

/// Thin wrapper around MethodChannel("de.haphone.app.test/sip_calls"), the
/// platform-channel bridge to the native SIP/Telecom layer. See
/// android/app/src/main/kotlin/de/haphone/app/test/SipChannelHandler.kt for
/// the native side of every method here.
class SipChannel {
  SipChannel._();
  static final SipChannel instance = SipChannel._();

  static const _channel = MethodChannel('de.haphone.app.test/sip_calls');

  /// Retries an invokeMethod call that might race the native side's
  /// channel-handler registration. Confirmed on a live device: when the
  /// FlutterEngine is pre-warmed (executeDartEntrypoint in
  /// HAPhoneTestApplication.onCreate, before MainActivity exists to
  /// attach), Dart's very first platform-channel call -- always
  /// hasValidCredentials, from RootScreen.initState() -- can be sent
  /// before MainActivity.configureFlutterEngine() has registered
  /// SipChannelHandler, and then never resolves (no exception, no
  /// timeout -- it just sits there) until something else, e.g. navigating
  /// away and back, happens to re-invoke it after the handler exists.
  /// Removing the pre-warm was tried and made it worse (no UI rendered at
  /// all), so this call-site retries instead: race each attempt against a
  /// short timeout and try again rather than hoping for a single lucky
  /// ordering.
  static Future<T?> _invokeResilient<T>(
    String method, [
    dynamic arguments,
    int maxAttempts = 15,
  ]) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _channel
            .invokeMethod<T>(method, arguments)
            .timeout(const Duration(milliseconds: 400));
      } on Exception {
        if (attempt == maxAttempts) rethrow;
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    return null;
  }

  Future<bool> hasValidCredentials() async {
    final result = await _invokeResilient<bool>('hasValidCredentials');
    return result ?? false;
  }

  Future<Map<String, String>> getCredentials() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('getCredentials');
    return (result ?? const {}).map((k, v) => MapEntry(k as String, v as String));
  }

  Future<void> saveCredentials({
    required String host,
    required String port,
    required String username,
    required String password,
  }) {
    return _channel.invokeMethod('saveCredentials', {
      'host': host,
      'port': port,
      'username': username,
      'password': password,
    });
  }

  Future<void> clearCredentials() => _channel.invokeMethod('clearCredentials');

  Future<void> register() => _channel.invokeMethod('register');
  Future<void> unregister() => _channel.invokeMethod('unregister');

  Future<void> makeCall(String number) => _channel.invokeMethod('makeCall', number);
  Future<void> hangup() => _channel.invokeMethod('hangup');
  Future<void> hold(bool onHold) => _channel.invokeMethod('hold', onHold);
  Future<void> mute(bool muted) => _channel.invokeMethod('mute', muted);
  Future<void> transfer(String number) => _channel.invokeMethod('transfer', number);
  Future<void> sendDtmf(String digit) => _channel.invokeMethod('sendDtmf', digit);

  /// OS-native device identifier (ANDROID_ID), used to identify this
  /// device to the HA-Phone backend during QR provisioning.
  Future<String?> getDeviceId() => _channel.invokeMethod<String>('getDeviceId');

  /// Current FCM push token, registered with the backend during QR
  /// provisioning so the box can wake this device for incoming calls.
  Future<String?> getFcmToken() => _channel.invokeMethod<String>('getFcmToken');

  // ---- Device auth (from /api/mobile/provision/complete) ----

  Future<void> saveDeviceAuth({
    required String apiHost,
    required String deviceId,
    required String deviceToken,
  }) {
    return _channel.invokeMethod('saveDeviceAuth', {
      'apiHost': apiHost,
      'deviceId': deviceId,
      'deviceToken': deviceToken,
    });
  }

  /// Keys apiHost, deviceId, deviceToken; values are '' when not paired via QR.
  Future<Map<String, String>> getDeviceAuth() async {
    final result = await _invokeResilient<Map<Object?, Object?>>('getDeviceAuth');
    return (result ?? const {}).map((k, v) => MapEntry(k as String, (v as String?) ?? ''));
  }

  // ---- Door stations ----

  /// Extension number -> DTMF door-open code, from /api/mobile/directory. Replaces the stored map.
  Future<void> setDoorCodes(Map<String, String> codes) => _channel.invokeMethod('setDoorCodes', codes);

  // ---- Second call (call waiting, consultation, conference) ----

  /// Answer the waiting call; the current one goes on hold.
  Future<bool> answerWaiting() async => await _channel.invokeMethod<bool>('answerWaiting') ?? false;
  Future<void> rejectWaiting() => _channel.invokeMethod('rejectWaiting');

  /// Makeln: swap between the on-screen and the held call.
  Future<bool> swapCalls() async => await _channel.invokeMethod<bool>('swapCalls') ?? false;

  /// 3-way conference of both calls (mixed in the app, no PBX change).
  Future<bool> mergeCalls() async => await _channel.invokeMethod<bool>('mergeCalls') ?? false;

  /// Connect the held party with the current one and leave (attended transfer).
  Future<bool> transferAttended() async => await _channel.invokeMethod<bool>('transferAttended') ?? false;

  /// Extension number -> labels of its Home Assistant door actions (from the directory).
  Future<void> setDoorActions(Map<String, List<String>> labels) => _channel.invokeMethod('setDoorActions', labels);

  /// Door stations with a PBX webhook (`door_open_remote`): the native ringing
  /// screen opens them without answering. Replaces the stored list.
  Future<void> setDoorOpenRemote(List<String> numbers) => _channel.invokeMethod('setDoorOpenRemote', numbers);

  // ---- Android Auto (native car screens, see android/.../car/) ----

  /// Directory for the car screens: maps {number, name, ext, door, openRemote} and the own number.
  Future<void> setCarDirectory(List<Map<String, Object>> entries, String selfNumber) =>
      _channel.invokeMethod('setCarDirectory', {'entries': entries, 'self': selfNumber});

  /// Favourite numbers for the car's Favoriten tab. Replaces the stored list.
  Future<void> setFavorites(List<String> numbers) => _channel.invokeMethod('setFavorites', numbers);

  /// Runs door action [index] of [number] on the PBX; throws PlatformException with a German message on failure.
  Future<void> runDoorAction(String number, int index) =>
      _channel.invokeMethod('runDoorAction', {'number': number, 'index': index});

  /// Sends the current call's door-open code as DTMF. No-op if the caller is no door station.
  Future<void> openDoor() => _channel.invokeMethod('openDoor');

  /// In-app appearance ('dark' | 'light' | 'system'), persisted natively for
  /// the ringing screen (IncomingCallActivity), which may start without Dart.
  Future<void> setAppearance(String mode) => _channel.invokeMethod('setAppearance', mode);

  // ---- Current call ----

  /// null when there is no call.
  Future<CurrentCall?> getCurrentCall() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('getCurrentCall');
    return raw == null ? null : CurrentCall.fromMap(raw);
  }

  // ---- Audio routing (Android Telecom endpoints) ----

  Future<AudioRoutes> getAudioRoutes() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('getAudioRoutes');
    return AudioRoutes.fromMap(raw ?? const {});
  }

  Future<void> setAudioRoute(String id) => _channel.invokeMethod('setAudioRoute', id);

  // ---- Local call history (recorded natively, survives app restarts) ----

  Future<List<CallHistoryEntry>> getCallHistory() async {
    final raw = await _channel.invokeMethod<List<Object?>>('getCallHistory');
    return (raw ?? const [])
        .map((e) => CallHistoryEntry.fromMap(e as Map<Object?, Object?>))
        .toList();
  }

  Future<void> deleteCallHistoryEntry(String id) => _channel.invokeMethod('deleteCallHistoryEntry', id);
  Future<void> clearCallHistory() => _channel.invokeMethod('clearCallHistory');

  /// 'registered' | 'failed' | 'unregistered' | 'unknown'
  Future<String> getRegistrationState() async {
    return await _channel.invokeMethod<String>('getRegistrationState') ?? 'unknown';
  }

  /// Native -> Dart calls -- currently just IncomingCallActivity's
  /// post-answer hand-off ("navigateTo", see MainActivity.kt). Only one
  /// handler at a time, matching the single MethodChannel instance wired
  /// natively.
  void setNavigationHandler(void Function(String route) onNavigate) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'navigateTo') {
        onNavigate(call.arguments as String);
      }
    });
  }
}

/// Platform view type showing the current call's incoming video (TextureView, native side).
const remoteVideoViewType = 'de.haphone.app.test/remote_video';

class CurrentCall {
  CurrentCall({
    required this.number,
    required this.name,
    required this.direction,
    required this.video,
    required this.doorCode,
    required this.state,
    required this.connectedAt,
    required this.secure,
    this.muted = false,
    this.onHold = false,
    this.other,
    this.conference = false,
    this.doorActions = const [],
  });

  factory CurrentCall.fromMap(Map<Object?, Object?> m) => CurrentCall(
        number: m['number'] as String? ?? '',
        name: m['name'] as String? ?? '',
        direction: m['direction'] as String? ?? '',
        video: m['video'] as bool? ?? false,
        doorCode: m['doorCode'] as String? ?? '',
        state: m['state'] as String? ?? '',
        connectedAt: (m['connectedAtMs'] as int? ?? 0) > 0
            ? DateTime.fromMillisecondsSinceEpoch(m['connectedAtMs'] as int)
            : null,
        secure: m['secure'] as bool? ?? false,
        muted: m['muted'] as bool? ?? false,
        onHold: m['onHold'] as bool? ?? false,
        other: m['other'] is Map ? CurrentCall.fromMap(m['other'] as Map<Object?, Object?>) : null,
        conference: m['conference'] as bool? ?? false,
        doorActions: ((m['doorActions'] as List<Object?>?) ?? const []).whereType<String>().toList(),
      );

  final String number;
  final String name;

  /// 'incoming' | 'outgoing'
  final String direction;

  /// The call carries (door station) video.
  final bool video;

  /// Non-empty when the other side is a door station.
  final String doorCode;

  /// 'ringing' | 'connecting' | 'confirmed' | 'waiting' (second call knocking)
  final String state;

  /// Set once the call was answered (SIP CONFIRMED).
  final DateTime? connectedAt;

  /// Signalling runs over TLS.
  final bool secure;

  final bool muted;
  final bool onHold;

  /// Second call: held behind this one, or ringing as call waiting (state 'waiting').
  final CurrentCall? other;

  /// Both calls are joined in a 3-way conference.
  final bool conference;

  bool get isWaiting => state == 'waiting';

  /// Home Assistant buttons of this door station ("Licht", "Garage"), index = action id.
  final List<String> doorActions;

  bool get isDoor => doorCode.isNotEmpty;
}

class AudioRoute {
  AudioRoute({required this.id, required this.name, required this.type});

  factory AudioRoute.fromMap(Map<Object?, Object?> m) => AudioRoute(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        type: m['type'] as String? ?? 'other',
      );

  final String id;
  final String name;

  /// 'earpiece' | 'speaker' | 'bluetooth' | 'headset' | 'other'
  final String type;
}

class AudioRoutes {
  AudioRoutes({required this.currentId, required this.routes});

  factory AudioRoutes.fromMap(Map<Object?, Object?> m) => AudioRoutes(
        currentId: m['current'] as String? ?? '',
        routes: ((m['routes'] as List<Object?>?) ?? const [])
            .map((e) => AudioRoute.fromMap(e as Map<Object?, Object?>))
            .toList(),
      );

  final String currentId;
  final List<AudioRoute> routes;

  AudioRoute? get current {
    for (final r in routes) {
      if (r.id == currentId) return r;
    }
    return null;
  }
}

class CallHistoryEntry {
  CallHistoryEntry({
    required this.id,
    required this.number,
    required this.name,
    required this.direction,
    required this.answered,
    required this.video,
    required this.startedAt,
    required this.duration,
  });

  factory CallHistoryEntry.fromMap(Map<Object?, Object?> m) => CallHistoryEntry(
        id: m['id'] as String? ?? '',
        number: m['number'] as String? ?? '',
        name: m['name'] as String? ?? '',
        direction: m['direction'] as String? ?? '',
        answered: m['answered'] as bool? ?? false,
        video: m['video'] as bool? ?? false,
        startedAt: DateTime.fromMillisecondsSinceEpoch(m['startedAtMs'] as int? ?? 0),
        duration: Duration(seconds: m['durationSec'] as int? ?? 0),
      );

  final String id;
  final String number;
  final String name;

  /// 'incoming' | 'outgoing'
  final String direction;
  final bool answered;
  final bool video;
  final DateTime startedAt;
  final Duration duration;

  bool get missed => direction == 'incoming' && !answered;
}
