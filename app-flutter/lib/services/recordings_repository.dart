import 'package:flutter/foundation.dart';

import '../models/recording.dart';
import 'api_client.dart';
import 'directory_repository.dart';
import 'pbx_audio.dart';

/// Call recordings of the own extension (GET /api/mobile/recordings,
/// HA-Phone 0.7.114), refreshed when the list or the Ich tab opens; no
/// polling. Also starts/stops the recording of a running call and keeps
/// which lines are being recorded, so that survives the call screen being
/// rebuilt.
class RecordingsRepository extends ChangeNotifier {
  RecordingsRepository({ApiClient? api, Future<DeviceAuth> Function()? authLoader, DateTime Function()? clock})
      : _api = api ?? ApiClient(),
        _authLoader = authLoader ?? DirectoryRepository.loadAuthFromNative,
        _clock = clock ?? DateTime.now;

  static final RecordingsRepository instance = RecordingsRepository();

  final ApiClient _api;
  final Future<DeviceAuth> Function() _authLoader;
  final DateTime Function() _clock;

  List<CallRecording> _recordings = const [];
  bool _allowed = false;
  bool _loaded = false;
  bool _loading = false;
  ApiException? _error;
  RecordingLines _live = const RecordingLines();
  bool _switching = false;

  /// Newest first.
  List<CallRecording> get recordings => _recordings;

  /// `allowed` of the last successful refresh.
  bool get isAllowed => _allowed;
  ApiException? get error => _error;
  bool get isLoading => _loading;

  /// True once a refresh succeeded (distinguishes "empty" from "not loaded").
  bool get hasLoaded => _loaded;
  bool get isUnsupported => _error?.kind == ApiErrorKind.unsupported;

  /// A start/stop request is on its way (the button is disabled meanwhile).
  bool get isSwitching => _switching;

  /// Start of the recording on the call line [lineKey] ([recordingLineKey]), null if not recorded.
  DateTime? recordingSince(String lineKey) => _live.since(lineKey);

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final list = await _api.fetchRecordings(await _authLoader());
      _recordings = list.recordings;
      _allowed = list.allowed;
      _loaded = true;
      _error = null;
    } on ApiException catch (e) {
      _error = e;
    } catch (e) {
      debugPrint('recordings refresh failed: $e');
      _error = const ApiException(ApiErrorKind.unreachable);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Deletes on the PBX first, then locally; rethrows [ApiException].
  Future<void> delete(CallRecording r) async {
    await _api.deleteRecording(await _authLoader(), r);
    _recordings = _recordings.where((e) => e.id != r.id).toList();
    notifyListeners();
  }

  /// Stream/download source of a recording for the player.
  Future<PbxAudioSource> audioSource(CallRecording r) async {
    final auth = await _authLoader();
    return PbxAudioSource(
      uri: _api.recordingAudioUri(auth, r),
      headers: ApiClient.authHeaders(auth),
      download: () => _api.downloadRecording(auth, r),
      tempFileName: 'recording_${r.id.hashCode}.wav',
    );
  }

  /// Starts recording the line [lineKey] whose other party is [peer];
  /// rethrows [ApiException] (403 not allowed, 409 no unique call, 502).
  Future<void> start({required String lineKey, required String peer}) => _switch(() async {
        await _api.startRecording(await _authLoader(), peer);
        _live = _live.started(lineKey, _clock());
      });

  /// Stops recording the line [lineKey]. A 409 (nothing running, e.g. the
  /// PBX already stopped it) still clears the indicator, then rethrows.
  Future<void> stop({required String lineKey, required String peer}) => _switch(() async {
        try {
          await _api.stopRecording(await _authLoader(), peer);
        } on ApiException catch (e) {
          if (e.statusCode == 409) _live = _live.stopped(lineKey);
          rethrow;
        }
        _live = _live.stopped(lineKey);
      });

  Future<void> _switch(Future<void> Function() action) async {
    if (_switching) return;
    _switching = true;
    notifyListeners();
    try {
      await action();
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('recording start/stop failed: $e');
      throw const ApiException(ApiErrorKind.unreachable);
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

  /// Forgets recorded lines that are no longer part of the call.
  void retainLines(Set<String> lineKeys) {
    final next = _live.retain(lineKeys);
    if (identical(next, _live)) return;
    _live = next;
    notifyListeners();
  }

  /// Forget everything (device unpaired).
  void clear() {
    _recordings = const [];
    _allowed = false;
    _loaded = false;
    _error = null;
    _live = const RecordingLines();
    notifyListeners();
  }
}
