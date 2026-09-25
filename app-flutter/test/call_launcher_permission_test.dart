import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/call_launcher.dart';

void main() {
  test('already granted: no second request', () async {
    var asked = false;
    final ok = await CallLauncher.ensureGranted(
      status: () async => true,
      request: () async => asked = true,
    );
    expect(ok, isTrue);
    expect(asked, isFalse);
  });

  test('not granted: asks and uses the answer', () async {
    expect(await CallLauncher.ensureGranted(status: () async => false, request: () async => true), isTrue);
    expect(await CallLauncher.ensureGranted(status: () async => false, request: () async => false), isFalse);
  });

  test('another request still open: falls back to the status instead of throwing', () async {
    var calls = 0;
    final ok = await CallLauncher.ensureGranted(
      status: () async => calls++ > 0, // granted by the time the busy request fails
      request: () async => throw PlatformException(code: 'PermissionHandler.PermissionManager', message: 'already running'),
    );
    expect(ok, isTrue);
  });
}
