import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/ring_settings.dart';

/// "Klingeln auf diesem Handy" over the MethodChannel (getRingPolicy /
/// setRingPolicy, native RingPolicyStore). Notifies again when a timed mute
/// runs out, so the Start pill switches back to "Klingelt hier" by itself.
class RingSettingsRepository extends ChangeNotifier {
  RingSettingsRepository({MethodChannel? channel, DateTime Function()? clock})
      : _channel = channel ?? _defaultChannel,
        _clock = clock ?? DateTime.now;

  static final RingSettingsRepository instance = RingSettingsRepository();

  static const _defaultChannel = MethodChannel('de.haphone.app.test/sip_calls');

  final MethodChannel _channel;
  final DateTime Function() _clock;

  RingSettings _settings = const RingSettings();
  bool _loaded = false;
  Timer? _expiry;

  RingSettings get settings => _settings;

  /// Label and end of the last mute chip tapped, so that chip stays selected.
  (String, DateTime)? muteChoice;
  bool get hasLoaded => _loaded;
  DateTime now() => _clock();

  bool get ringsNow => _settings.ringsAt(_clock());

  Future<void> load() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('getRingPolicy');
      if (raw != null) _apply(RingSettings.fromMap(raw));
      _loaded = true;
    } on PlatformException catch (e) {
      debugPrint('getRingPolicy failed: $e');
    } on MissingPluginException {
      // Not on Android (tests, other platforms): keep the default.
    }
    notifyListeners();
  }

  /// Stores [next] natively; the UI updates at once and reverts on failure.
  Future<void> update(RingSettings next) async {
    final before = _settings;
    _apply(next);
    notifyListeners();
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('setRingPolicy', next.toMap());
      if (raw != null) _apply(RingSettings.fromMap(raw));
    } on PlatformException catch (e) {
      debugPrint('setRingPolicy failed: $e');
      _apply(before);
      notifyListeners();
      rethrow;
    } on MissingPluginException {
      // Keep the local value (tests).
    }
    notifyListeners();
  }

  void _apply(RingSettings s) {
    _settings = s;
    _expiry?.cancel();
    final until = s.mutedUntil;
    if (until == null) return;
    final left = until.difference(_clock());
    if (left.isNegative) return;
    _expiry = Timer(left + const Duration(seconds: 1), notifyListeners);
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }
}
