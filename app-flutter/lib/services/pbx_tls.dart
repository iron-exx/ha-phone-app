import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Pinned TLS to the PBX (HA-Phone 0.7.130+), the Dart twin of the native `PbxTls`.
///
/// The box has one self-signed cert for SIP TLS and the HTTPS API (port 8443). Its
/// SHA-256 comes with the pairing QR code, or once from /api/mobile/config for devices
/// paired before. Only exactly that cert is accepted; host names are not checked because
/// the box is reached by LAN IP and tailnet IP alike.

String normalizePin(String pin) => pin.replaceAll(':', '').trim().toLowerCase();

bool isValidPin(String pin) => RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizePin(pin));

bool certMatchesPin(List<int> der, String pin) {
  final want = normalizePin(pin);
  return want.isNotEmpty && sha256.convert(der).toString() == want;
}

/// One HTTP client per pin. No trusted roots at all: every cert, even a publicly signed
/// one, goes through the pin check in badCertificateCallback.
class PinnedClients {
  PinnedClients._();

  static final Map<String, http.Client> _clients = {};

  static http.Client forPin(String pin) {
    final key = normalizePin(pin);
    return _clients.putIfAbsent(key, () {
      final io = HttpClient(context: SecurityContext(withTrustedRoots: false))
        ..connectionTimeout = const Duration(seconds: 8)
        ..badCertificateCallback = (cert, host, port) => certMatchesPin(cert.der, key);
      return IOClient(io);
    });
  }
}
