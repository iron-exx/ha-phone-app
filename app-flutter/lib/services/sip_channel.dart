import 'package:flutter/services.dart';

/// Thin wrapper around MethodChannel("de.haphone.app.test/sip_calls"), the
/// platform-channel bridge to the native SIP/Telecom layer. See
/// android/app/src/main/kotlin/de/haphone/app/test/SipChannelHandler.kt for
/// the native side of every method here.
class SipChannel {
  SipChannel._();
  static final SipChannel instance = SipChannel._();

  static const _channel = MethodChannel('de.haphone.app.test/sip_calls');

  /// Retries an invokeMethod call that might race the native side's
  /// channel-handler registration. Confirmed on a live device: when the
  /// FlutterEngine is pre-warmed (executeDartEntrypoint in
  /// HAPhoneTestApplication.onCreate, before MainActivity exists to
  /// attach), Dart's very first platform-channel call -- always
  /// hasValidCredentials, from HomeScreen.initState() -- can be sent
  /// before MainActivity.configureFlutterEngine() has registered
  /// SipChannelHandler, and then never resolves (no exception, no
  /// timeout -- it just sits there) until something else, e.g. navigating
  /// away and back, happens to re-invoke it after the handler exists.
  /// Removing the pre-warm was tried and made it worse (no UI rendered at
  /// all), so this call-site retries instead: race each attempt against a
  /// short timeout and try again rather than hoping for a single lucky
  /// ordering.
  static Future<T?> _invokeResilient<T>(
    String method, [
    dynamic arguments,
    int maxAttempts = 15,
  ]) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _channel
            .invokeMethod<T>(method, arguments)
            .timeout(const Duration(milliseconds: 400));
      } on Exception {
        if (attempt == maxAttempts) rethrow;
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    return null;
  }

  Future<bool> hasValidCredentials() async {
    final result = await _invokeResilient<bool>('hasValidCredentials');
    return result ?? false;
  }

  Future<Map<String, String>> getCredentials() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('getCredentials');
    return (result ?? const {}).map((k, v) => MapEntry(k as String, v as String));
  }

  Future<void> saveCredentials({
    required String host,
    required String port,
    required String username,
    required String password,
  }) {
    return _channel.invokeMethod('saveCredentials', {
      'host': host,
      'port': port,
      'username': username,
      'password': password,
    });
  }

  Future<void> clearCredentials() => _channel.invokeMethod('clearCredentials');

  Future<void> register() => _channel.invokeMethod('register');
  Future<void> unregister() => _channel.invokeMethod('unregister');

  Future<void> makeCall(String number) => _channel.invokeMethod('makeCall', number);
  Future<void> hangup() => _channel.invokeMethod('hangup');
  Future<void> hold(bool onHold) => _channel.invokeMethod('hold', onHold);
  Future<void> mute(bool muted) => _channel.invokeMethod('mute', muted);
  Future<void> transfer(String number) => _channel.invokeMethod('transfer', number);
  Future<void> sendDtmf(String digit) => _channel.invokeMethod('sendDtmf', digit);

  /// OS-native device identifier (ANDROID_ID), used to identify this
  /// device to the HA-Phone backend during QR provisioning.
  Future<String?> getDeviceId() => _channel.invokeMethod<String>('getDeviceId');

  /// Current FCM push token, registered with the backend during QR
  /// provisioning so the box can wake this device for incoming calls.
  Future<String?> getFcmToken() => _channel.invokeMethod<String>('getFcmToken');

  /// Native -> Dart calls -- currently just IncomingCallActivity's
  /// post-answer hand-off ("navigateTo", see MainActivity.kt). Only one
  /// handler at a time, matching the single MethodChannel instance wired
  /// natively.
  void setNavigationHandler(void Function(String route) onNavigate) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'navigateTo') {
        onNavigate(call.arguments as String);
      }
    });
  }
}
