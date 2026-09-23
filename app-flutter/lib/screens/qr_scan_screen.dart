import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/sip_channel.dart';

enum _ScreenState { checkingPermission, permissionDenied, scanning, processing, error }

/// QR-scan-to-pair flow: scans a `haphone://provision?t=<jwt>&host=<ip:port>`
/// code shown by the HA-Phone admin UI, exchanges the one-time token for
/// real SIP credentials via POST /api/mobile/provision/complete, and stores
/// them via SipChannel -- same storage HomeScreen/SettingsScreen already
/// read, so no separate "provisioned via QR" state is needed.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  _ScreenState _state = _ScreenState.checkingPermission;
  String _errorMessage = '';
  bool _handled = false; // guards against onDetect firing again before we stop the camera

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _state = status.isGranted ? _ScreenState.scanning : _ScreenState.permissionDenied;
    });
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;

    String? rawValue;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.startsWith('haphone://provision')) {
        rawValue = value;
        break;
      }
    }
    if (rawValue == null) return;

    _handled = true;
    await _controller.stop();

    final uri = Uri.parse(rawValue);
    final token = uri.queryParameters['t'];
    final host = uri.queryParameters['host'];
    if (token == null || host == null) {
      _showError('QR-Code ungültig');
      return;
    }

    if (!mounted) return;
    setState(() => _state = _ScreenState.processing);
    await _completeProvisioning(token: token, host: host);
  }

  Future<void> _completeProvisioning({required String token, required String host}) async {
    try {
      final deviceId = await SipChannel.instance.getDeviceId();
      final fcmToken = await SipChannel.instance.getFcmToken();

      final response = await http.post(
        Uri.parse('http://$host/api/mobile/provision/complete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'provisioning_token': token,
          'push_token': fcmToken ?? '',
          'os_device_id': deviceId ?? '',
          'app_version': '0.1.0',
          'device_name': '',
        }),
      );

      if (response.statusCode == 400) {
        _showError('QR-Code abgelaufen');
        return;
      }
      if (response.statusCode == 403) {
        _showError('QR-Code schon verwendet');
        return;
      }
      if (response.statusCode != 200) {
        _showError('Netzwerkfehler');
        return;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['success'] != true) {
        _showError('Netzwerkfehler');
        return;
      }

      final sipDomain = body['sip_domain'] as String? ?? '';
      final sipPort = body['sip_port'];
      final sipUsername = body['sip_username'] as String? ?? '';
      final sipPassword = body['sip_password'] as String? ?? '';

      // sip_domain is "ip:port" -- split on the LAST colon for the host
      // part, but always prefer the separate sip_port field for the port
      // itself, falling back to the domain's own suffix only if sip_port
      // is somehow missing.
      final lastColon = sipDomain.lastIndexOf(':');
      final sipHost = lastColon > 0 ? sipDomain.substring(0, lastColon) : sipDomain;
      final domainPort = lastColon > 0 ? sipDomain.substring(lastColon + 1) : '';
      final port = sipPort != null ? sipPort.toString() : domainPort;

      await SipChannel.instance.saveCredentials(
        host: sipHost,
        port: port,
        username: sipUsername,
        password: sipPassword,
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      _showError('Netzwerkfehler');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _state = _ScreenState.error;
    });
  }

  Future<void> _rescan() async {
    _handled = false;
    setState(() => _state = _ScreenState.scanning);
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR-Code scannen')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _ScreenState.checkingPermission:
        return const Center(child: CircularProgressIndicator());
      case _ScreenState.permissionDenied:
        return _buildMessage(
          context,
          icon: Icons.camera_alt_outlined,
          message: 'Kamera-Berechtigung wird zum Scannen des QR-Codes benötigt.',
          actionLabel: 'Erneut versuchen',
          onAction: _checkPermission,
        );
      case _ScreenState.scanning:
        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: _controller, onDetect: _onDetect),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                color: Colors.black54,
                padding: const EdgeInsets.all(16),
                child: const Text(
                  'QR-Code der HA-Phone-Box scannen',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        );
      case _ScreenState.processing:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Gerät wird eingerichtet...'),
            ],
          ),
        );
      case _ScreenState.error:
        return _buildMessage(
          context,
          icon: Icons.error_outline,
          message: _errorMessage,
          actionLabel: 'Neu scannen',
          onAction: _rescan,
        );
    }
  }

  Widget _buildMessage(
    BuildContext context, {
    required IconData icon,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
