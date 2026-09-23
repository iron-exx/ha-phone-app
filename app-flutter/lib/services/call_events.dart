import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sip_channel.dart';

sealed class CallEvent {}

class RegistrationStateEvent extends CallEvent {
  RegistrationStateEvent(this.state);
  final String state;
}

/// state: 'ringing' | 'connecting' | 'active' | 'confirmed' | 'disconnected'.
/// 'confirmed' = SIP call answered and media up (drives the call timer).
class CallStateEvent extends CallEvent {
  CallStateEvent({
    required this.callId,
    required this.direction,
    required this.state,
    this.disconnectReason,
  });
  final String callId;
  final String direction;
  final String state;
  final String? disconnectReason;
}

/// Audio endpoint list or selection changed during a call.
class AudioRouteEvent extends CallEvent {
  AudioRouteEvent(this.routes);
  final AudioRoutes routes;
}

/// A call-history entry was added or finished (reload via SipChannel.getCallHistory).
class CallHistoryChangedEvent extends CallEvent {}

/// Wraps EventChannel("de.haphone.app.test/call_events"). See
/// android/app/src/main/kotlin/de/haphone/app/test/CallEventBus.kt for the
/// native side -- Phase 1 wires coarse registration/call-lifecycle events
/// only (that file's doc comment explains what's deliberately not wired
/// yet). Consumed by the active-call screen, the Anrufe tab (history
/// reloads) and the Ich tab (registration state).
class CallEvents {
  CallEvents._();
  static final CallEvents instance = CallEvents._();

  static const _channel = EventChannel('de.haphone.app.test/call_events');

  Stream<CallEvent>? _stream;

  /// Last call-ended event, kept because a call can fail before the
  /// active-call screen has subscribed. Cleared before each new call.
  CallStateEvent? lastDisconnected;

  Stream<CallEvent> get stream {
    return _stream ??= _channel
        .receiveBroadcastStream()
        .map(_parse)
        .where((e) => e != null)
        .cast<CallEvent>()
        .asBroadcastStream();
  }

  /// Keeps the native EventSink attached for the app's lifetime so no event is dropped.
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    stream.listen(
      (event) {
        if (event is CallStateEvent && event.state == 'disconnected') {
          lastDisconnected = event;
        }
      },
      onError: (Object e) => debugPrint('call events error: $e'),
    );
  }

  /// Unknown event types are skipped (null) instead of throwing, so a newer
  /// native side can add events without breaking an older Dart build.
  CallEvent? _parse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    switch (map['type']) {
      case 'registrationState':
        return RegistrationStateEvent(map['state'] as String? ?? 'unknown');
      case 'callState':
        return CallStateEvent(
          callId: map['callId'] as String? ?? '',
          direction: map['direction'] as String? ?? '',
          state: map['state'] as String? ?? '',
          disconnectReason: map['disconnectReason'] as String?,
        );
      case 'audioRoute':
        return AudioRouteEvent(AudioRoutes.fromMap(map.cast<Object?, Object?>()));
      case 'callHistoryChanged':
        return CallHistoryChangedEvent();
      default:
        debugPrint('ignoring unknown call event type: ${map['type']}');
        return null;
    }
  }
}
