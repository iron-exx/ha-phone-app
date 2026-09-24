import 'package:flutter/foundation.dart';

import '../models/extension_status.dart';
import '../models/presence.dart';
import 'api_client.dart';
import 'directory_repository.dart';
import 'foreground_poller.dart';

/// Live presence + line state of all extensions (GET /api/mobile/presence),
/// polled every 10 s while the shell is up and the app is in the foreground
/// (the call-flip banner watches the own line on every tab). Also sets the
/// own presence (PUT).
class PresenceRepository extends ChangeNotifier {
  PresenceRepository({
    ApiClient? api,
    Future<DeviceAuth> Function()? authLoader,
    Duration pollInterval = const Duration(seconds: 10),
  })  : _api = api ?? ApiClient(),
        _authLoader = authLoader ?? DirectoryRepository.loadAuthFromNative {
    _poller = ForegroundPoller(interval: pollInterval, onTick: refresh);
  }

  static final PresenceRepository instance = PresenceRepository();

  final ApiClient _api;
  final Future<DeviceAuth> Function() _authLoader;
  late final ForegroundPoller _poller;

  PresenceSnapshot? _snapshot;
  DateTime? _updatedAt;
  ApiException? _error;
  bool _loading = false;
  bool _saving = false;

  /// Last successful snapshot (or optimistic update), null if never loaded.
  PresenceSnapshot? get snapshot => _snapshot;

  /// When the last successful refresh arrived (line states are that fresh).
  DateTime? get updatedAt => _updatedAt;

  /// Error of the last refresh; cleared on success.
  ApiException? get error => _error;

  /// True while the PBX is too old for /api/mobile/presence.
  bool get isUnsupported => _error?.kind == ApiErrorKind.unsupported;
  bool get isSaving => _saving;
  bool get isPolling => _poller.isRunning;

  /// Status for an extension, null if the snapshot doesn't know it.
  ExtensionStatus? statusFor(String number) => _snapshot?.statusFor(number);

  /// Called by the shell: true while it is on screen.
  void setVisible(bool visible) => _poller.active = visible;

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final fresh = await _api.fetchPresence(await _authLoader());
      // Don't let a poll that started before a PUT overwrite the optimistic value.
      if (!_saving) _snapshot = fresh;
      _updatedAt = DateTime.now();
      _error = null;
    } on ApiException catch (e) {
      _error = e;
    } catch (e) {
      debugPrint('presence refresh failed: $e');
      _error = const ApiException(ApiErrorKind.unreachable);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Sets the own presence optimistically; reverts and rethrows the
  /// [ApiException] on failure so the UI can show a SnackBar.
  Future<void> setOwn(Presence presence) async {
    final before = _snapshot;
    _snapshot = (before ?? const PresenceSnapshot()).withOwnPresence(presence);
    _saving = true;
    notifyListeners();
    try {
      final stored = await _api.setPresence(await _authLoader(), presence);
      _snapshot = (_snapshot ?? const PresenceSnapshot()).withOwnPresence(stored);
    } on ApiException {
      _snapshot = before;
      rethrow;
    } catch (e) {
      debugPrint('setPresence failed: $e');
      _snapshot = before;
      throw const ApiException(ApiErrorKind.unreachable);
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Forget everything (device unpaired).
  void clear() {
    _snapshot = null;
    _updatedAt = null;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }
}
