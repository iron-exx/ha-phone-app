import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every native library linked into the app has its licence on the licence page', () async {
    final entries = await bundledLicenses().toList();
    final packages = entries.expand((e) => e.packages).toSet();
    for (final name in ['PJSIP (pjproject)', 'OpenSSL', 'Opus', 'libsrtp', 'Tailscale', 'wireguard-go', 'Go']) {
      expect(packages, contains(name));
    }
    final pjsip = entries.firstWhere((e) => e.packages.contains('PJSIP (pjproject)'));
    expect(pjsip.paragraphs.map((p) => p.text).join(' '), contains('GNU GENERAL PUBLIC LICENSE'));
  });
}
