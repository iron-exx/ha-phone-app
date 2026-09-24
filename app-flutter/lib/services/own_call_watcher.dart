import 'dart:async';

import 'package:flutter/foundation.dart';

import 'call_events.dart';
import 'sip_channel.dart';

/// This app's current call (re-read from the native side on every call
/// state event) and when it last ended. Used by the green "Gespräch läuft"
/// bar and by the call-flip card, which must not offer "Hierher holen" for
/// the app's own call.
class OwnCallWatcher extends ChangeNotifier {
  OwnCallWatcher() {
    _events = CallEvents.instance.stream.listen((e) {
      if (e is CallStateEvent) unawaited(refresh());
    });
    unawaited(refresh());
  }

  StreamSubscription<CallEvent>? _events;
  CurrentCall? _call;
  DateTime? _endedAt;
  bool _disposed = false;

  CurrentCall? get call => _call;

  /// When the app's own call last ended (its "busy" may still be in the
  /// presence snapshot), null if none ended while watching.
  DateTime? get endedAt => _endedAt;

  Future<void> refresh() async {
    try {
      final call = await SipChannel.instance.getCurrentCall();
      if (_disposed) return;
      if (_call != null && call == null) _endedAt = DateTime.now();
      _call = call;
      notifyListeners();
    } catch (_) {
      // No channel (tests) or no call: nothing to show.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    super.dispose();
  }
}
