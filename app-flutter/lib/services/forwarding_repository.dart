import 'package:flutter/foundation.dart';

import '../models/forwarding.dart';
import 'api_client.dart';
import 'directory_repository.dart';

/// Own forwarding rules per presence status (GET/PUT /api/mobile/forwarding).
/// Saving always PUTs the full list; updates are optimistic and reverted
/// when the PBX rejects them.
class ForwardingRepository extends ChangeNotifier {
  ForwardingRepository({ApiClient? api, Future<DeviceAuth> Function()? authLoader})
      : _api = api ?? ApiClient(),
        _authLoader = authLoader ?? DirectoryRepository.loadAuthFromNative;

  static final ForwardingRepository instance = ForwardingRepository();

  final ApiClient _api;
  final Future<DeviceAuth> Function() _authLoader;

  List<ForwardingRule> _rules = const [];
  bool _loaded = false;
  bool _loading = false;
  bool _saving = false;
  ApiException? _error;

  List<ForwardingRule> get rules => _rules;
  bool get hasLoaded => _loaded;
  bool get isLoading => _loading;
  bool get isSaving => _saving;
  ApiException? get error => _error;
  bool get isUnsupported => _error?.kind == ApiErrorKind.unsupported;

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final fresh = await _api.fetchForwarding(await _authLoader());
      if (!_saving) _rules = fresh;
      _loaded = true;
      _error = null;
    } on ApiException catch (e) {
      _error = e;
    } catch (e) {
      debugPrint('forwarding refresh failed: $e');
      _error = const ApiException(ApiErrorKind.unreachable);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Sets the rule for [status] + [direction] (null = "Normal klingeln").
  /// Reverts and rethrows [ApiException] on failure.
  Future<void> setRule(String status, ForwardDirection direction, ForwardingRule? rule) =>
      save(replaceRule(_rules, status, direction, rule));

  /// PUTs the full list optimistically; reverts and rethrows on failure.
  Future<void> save(List<ForwardingRule> rules) async {
    final before = _rules;
    _rules = rules;
    _saving = true;
    notifyListeners();
    try {
      _rules = await _api.saveForwarding(await _authLoader(), rules);
    } on ApiException {
      _rules = before;
      rethrow;
    } catch (e) {
      debugPrint('saveForwarding failed: $e');
      _rules = before;
      throw const ApiException(ApiErrorKind.unreachable);
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Forget everything (device unpaired).
  void clear() {
    _rules = const [];
    _loaded = false;
    _error = null;
    notifyListeners();
  }
}
