import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/tailnet_status.dart';

void main() {
  test('parses the native status map', () {
    final s = TailnetStatus.fromMap({
      'configured': true,
      'running': true,
      'state': 6,
      'selfIp': '100.80.1.2',
      'direct': true,
    });
    expect(s.configured, isTrue);
    expect(s.running, isTrue);
    expect(s.selfIp, '100.80.1.2');
  });

  test('running tunnel is ok and says how it is connected', () {
    final t = describeTailnet(const TailnetStatus(configured: true, running: true, direct: false, selfIp: '100.80.1.2'));
    expect(t.ok, isTrue);
    expect(t.action, isNull);
    expect(t.detail, contains('Relay'));
    expect(t.detail, contains('100.80.1.2'));
  });

  test('missing consent asks to set it up', () {
    final t = describeTailnet(const TailnetStatus(configured: true, consentNeeded: true));
    expect(t.ok, isFalse);
    expect(t.action, 'Einrichten');
  });

  test('pending login asks to sign in', () {
    final t = describeTailnet(const TailnetStatus(configured: true, state: TailnetStatus.stateNeedsLogin));
    expect(t.action, 'Anmelden');
  });

  test('another VPN wins over everything but a running tunnel', () {
    final t = describeTailnet(const TailnetStatus(configured: true, revoked: true, consentNeeded: true));
    expect(t.detail, contains('anderes VPN'));
  });
}
