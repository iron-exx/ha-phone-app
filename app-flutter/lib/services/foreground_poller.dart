import 'dart:async';

import 'package:flutter/widgets.dart';

/// Calls [onTick] every [interval] while it is [active] AND the app is in the
/// foreground (AppLifecycleState.resumed). Ticks once immediately whenever it
/// (re)starts, so data is fresh when a tab opens or the app comes back.
class ForegroundPoller with WidgetsBindingObserver {
  ForegroundPoller({required this.interval, required this.onTick});

  final Duration interval;
  final Future<void> Function() onTick;

  Timer? _timer;
  bool _active = false;
  bool _observing = false;
  bool _foreground = true;

  bool get isActive => _active;
  bool get isRunning => _timer != null;

  set active(bool value) {
    if (value == _active) return;
    _active = value;
    if (value && !_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      final state = WidgetsBinding.instance.lifecycleState;
      _foreground = state == null || state == AppLifecycleState.resumed;
    } else if (!value && _observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    _update();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _update();
  }

  void _update() {
    final shouldRun = _active && _foreground;
    if (shouldRun && _timer == null) {
      unawaited(_tick());
      _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
    } else if (!shouldRun && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  Future<void> _tick() async {
    try {
      await onTick();
    } catch (e) {
      debugPrint('poll failed: $e');
    }
  }

  void dispose() => active = false;
}
