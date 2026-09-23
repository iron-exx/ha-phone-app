import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screens/active_call_screen.dart';
import 'screens/dialpad_screen.dart';
import 'screens/qr_scan_screen.dart';
import 'screens/settings_screen.dart';
import 'services/call_events.dart';
import 'services/sip_channel.dart';

void main() {
  runApp(const HAPhoneApp());
}

class HAPhoneApp extends StatefulWidget {
  const HAPhoneApp({super.key});

  @override
  State<HAPhoneApp> createState() => _HAPhoneAppState();
}

class _HAPhoneAppState extends State<HAPhoneApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Native -> Dart hand-off, e.g. IncomingCallActivity's post-answer
    // navigation (see SipChannel.setNavigationHandler / MainActivity.kt).
    SipChannel.instance.setNavigationHandler(_handleNativeRoute);
  }

  void _handleNativeRoute(String route) {
    if (route == 'active_call') {
      _navigatorKey.currentState?.pushNamedAndRemoveUntil('/active-call', (r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'HA-Phone',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/dialpad': (_) => const DialpadScreen(),
        '/active-call': (_) => const ActiveCallScreen(),
        '/qr-scan': (_) => const QrScanScreen(),
      },
    );
  }
}

/// Replaces the old native MainActivity's Compose home screen. Shows
/// setup status and routes to Settings (manual SIP entry) or QR-Scan
/// pairing (qr_scan_screen.dart) to get credentials, or to the Dialpad
/// once provisioned.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checking = true;
  bool _provisioned = false;

  @override
  void initState() {
    super.initState();
    CallEvents.instance.start();
    _refresh();
    // Fix: this request existed in the old native Compose MainActivity but
    // was dropped/never ported when MainActivity became a FlutterActivity
    // (Phase 1 port) -- without it, incoming-call push notifications are
    // silently suppressed on Android 13+.
    [Permission.notification, Permission.microphone].request();
  }

  Future<void> _refresh() async {
    final ok = await SipChannel.instance.hasValidCredentials();
    if (ok) {
      SipChannel.instance.register().catchError((Object e) {
        debugPrint('SIP register failed: $e');
      });
    }
    if (!mounted) return;
    setState(() {
      _provisioned = ok;
      _checking = false;
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).pushNamed('/settings');
    _refresh();
  }

  Future<void> _openQrScan() async {
    await Navigator.of(context).pushNamed('/qr-scan');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HA-Phone'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
        ],
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: _provisioned
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _provisioned ? 'HA-Phone bereit' : 'Nicht eingerichtet',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!_provisioned) ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('QR-Code scannen'),
                      onPressed: _openQrScan,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.settings),
                      label: const Text('SIP-Zugangsdaten manuell eingeben'),
                      onPressed: _openSettings,
                    ),
                  ] else
                    FilledButton.icon(
                      icon: const Icon(Icons.dialpad),
                      label: const Text('Anrufen (Dialpad)'),
                      onPressed: () => Navigator.of(context).pushNamed('/dialpad'),
                    ),
                ],
              ),
            ),
    );
  }
}
