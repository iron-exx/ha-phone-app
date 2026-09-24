/// At most one run of a refresh at a time: a call while one is running gets
/// that run's future, so pull-to-refresh waits for a poll already in flight
/// instead of returning at once.
class SingleFlight {
  Future<void>? _running;

  bool get isRunning => _running != null;

  Future<void> run(Future<void> Function() task) {
    final running = _running;
    if (running != null) return running;
    late final Future<void> current;
    current = task().whenComplete(() {
      if (identical(_running, current)) _running = null;
    });
    return _running = current;
  }

  /// Forget the running future (after a reset): the next [run] starts anew.
  void reset() => _running = null;
}
