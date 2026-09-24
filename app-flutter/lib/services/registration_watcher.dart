import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/registration_ui.dart';
import 'call_events.dart';
import 'sip_channel.dart';

/// Live SIP registration state for the Start pill and the Wählen chip:
/// read once from the native side, then kept current from
/// RegistrationStateEvent.
class RegistrationWatcher extends ChangeNotifier {
  RegistrationWatcher();

  static final RegistrationWatcher instance = RegistrationWatcher();

  RegistrationUi _state = RegistrationUi.connecting;
  StreamSubscription<CallEvent>? _events;

  RegistrationUi get state => _state;

  /// Starts listening (idempotent) and re-reads the current state.
  Future<void> start() async {
    _events ??= CallEvents.instance.stream.listen((e) {
      if (e is RegistrationStateEvent) _set(RegistrationUi.fromState(e.state));
    });
    try {
      _set(RegistrationUi.fromState(await SipChannel.instance.getRegistrationState()));
    } catch (e) {
      debugPrint('getRegistrationState failed: $e');
    }
  }

  void _set(RegistrationUi s) {
    if (s == _state) return;
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}
