import 'package:flutter/foundation.dart';

import '../utils/diagnostics_report.dart';
import 'api_client.dart';
import 'directory_repository.dart';

/// Result of [DiagnosticsService.probe].
class PbxProbe {
  const PbxProbe(this.reachability, this.features);
  final Reachability reachability;
  final List<FeatureCheck> features;
}

/// Checks the PBX for the Diagnose screen: response time of
/// GET /api/mobile/presence and which app features its version offers.
class DiagnosticsService {
  DiagnosticsService({ApiClient? api, Future<DeviceAuth> Function()? authLoader})
      : _api = api ?? ApiClient(),
        _authLoader = authLoader ?? DirectoryRepository.loadAuthFromNative;

  final ApiClient _api;
  final Future<DeviceAuth> Function() _authLoader;

  Future<PbxProbe> probe() async {
    final DeviceAuth auth;
    try {
      auth = await _authLoader();
    } catch (e) {
      debugPrint('diagnostics: auth unavailable: $e');
      return const PbxProbe(Reachability.failed(ApiException(ApiErrorKind.notPaired)), []);
    }
    final watch = Stopwatch()..start();
    final presenceError = await _check(() => _api.fetchPresence(auth));
    watch.stop();
    // Any HTTP answer (even 404/401) proves the box is reachable.
    if (presenceError != null &&
        (presenceError.kind == ApiErrorKind.unreachable || presenceError.kind == ApiErrorKind.notPaired)) {
      return PbxProbe(Reachability.failed(presenceError), const []);
    }
    final reachability = Reachability.ok(watch.elapsedMilliseconds);
    final others = await Future.wait([
      _check(() => _api.fetchVoicemail(auth)),
      _check(() => _api.fetchForwarding(auth)),
      _check(() => _api.fetchCalls(auth, limit: 1)),
      _check(() => _api.fetchRecordings(auth)),
    ]);
    return PbxProbe(reachability, [
      _feature('Präsenz', presenceError, kMinPbxVersionPhase3),
      _feature('Voicemail', others[0], kMinPbxVersionPhase3),
      _feature('Weiterleitungen', others[1], kMinPbxVersionPhase5),
      _feature('Anrufliste der Anlage', others[2], kMinPbxVersionPhase5),
      _feature('Gesprächsaufzeichnung', others[3], kMinPbxVersionPhase6),
    ]);
  }

  FeatureCheck _feature(String label, ApiException? error, String minVersion) =>
      FeatureCheck(label, FeatureSupport.fromError(error), minVersion: minVersion, error: error);

  /// Runs [call]; returns its ApiException or null on success.
  Future<ApiException?> _check(Future<Object?> Function() call) async {
    try {
      await call();
      return null;
    } on ApiException catch (e) {
      return e;
    } catch (e) {
      debugPrint('diagnostics check failed: $e');
      return const ApiException(ApiErrorKind.server);
    }
  }
}
