import 'package:flutter/foundation.dart';

import '../models/reachability.dart';
import '../utils/reach_checks.dart';
import 'reachability_service.dart';
import 'ring_settings_repository.dart';

/// Last reachability snapshot for the amber warning dot on the Ich tab and the
/// Erreichbarkeit screen. Refreshed on start, on resume and after "Beheben".
class ReachabilityRepository extends ChangeNotifier {
  ReachabilityRepository({ReachabilityService? service, RingSettingsRepository? ring})
      : _service = service ?? ReachabilityService.instance,
        _ring = ring ?? RingSettingsRepository.instance {
    _ring.addListener(notifyListeners);
  }

  static final ReachabilityRepository instance = ReachabilityRepository();

  final ReachabilityService _service;
  final RingSettingsRepository _ring;
  ReachabilitySnapshot? _snapshot;
  bool _loading = false;

  ReachabilitySnapshot? get snapshot => _snapshot;
  bool get isLoading => _loading;
  RingSettingsRepository get ring => _ring;

  bool get hasProblems => hasReachProblems(_snapshot, _ring.settings, _ring.now());

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final s = await _service.load();
      if (s != null) _snapshot = s;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ring.removeListener(notifyListeners);
    super.dispose();
  }
}
