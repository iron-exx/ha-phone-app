import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake native side for SipChannel/CallEvents in widget tests.
///
/// [responses] maps method name -> value (or a function of the call's
/// arguments). Every call is recorded in [calls]. Events are pushed with
/// [emit]. CallEvents is a singleton that listens to the EventChannel only
/// once per test isolate, and MockStreamHandler's sink dies at each test's
/// teardown -- so events are injected as raw platform messages instead.
class FakeSip {
  FakeSip([Map<String, Object? Function(Object? args)>? responses])
      : responses = {...?responses};

  static const _method = MethodChannel('de.haphone.app.test/sip_calls');
  static const _events = EventChannel('de.haphone.app.test/call_events');

  final Map<String, Object? Function(Object? args)> responses;
  final List<MethodCall> calls = [];

  void install() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_method, (call) async {
      calls.add(call);
      final r = responses[call.method];
      return r?.call(call.arguments);
    });
    messenger.setMockMethodCallHandler(MethodChannel(_events.name), (_) async => null);
  }

  void uninstall() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_method, null);
    messenger.setMockMethodCallHandler(MethodChannel(_events.name), null);
  }

  void emit(Map<String, Object?> event) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      _events.name,
      _events.codec.encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  Iterable<MethodCall> callsTo(String method) => calls.where((c) => c.method == method);
}

Map<String, Object?> historyEntry({
  required String id,
  required String number,
  String name = '',
  String direction = 'incoming',
  bool answered = true,
  bool video = false,
  required DateTime startedAt,
  int durationSec = 0,
}) =>
    {
      'id': id,
      'number': number,
      'name': name,
      'direction': direction,
      'answered': answered,
      'video': video,
      'startedAtMs': startedAt.millisecondsSinceEpoch,
      'durationSec': durationSec,
    };
