import 'package:flutter/material.dart';

import 'screens/active_call_screen.dart';
import 'screens/dialpad_screen.dart';
import 'screens/qr_scan_screen.dart';
import 'screens/root_screen.dart';
import 'screens/settings_screen.dart';
import 'services/sip_channel.dart';
import 'theme/app_theme.dart';

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
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (_) => const RootScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/dialpad': (_) => const DialpadScreen(),
        '/active-call': (_) => const ActiveCallScreen(),
        '/qr-scan': (_) => const QrScanScreen(),
      },
    );
  }
}
