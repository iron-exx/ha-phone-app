import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/doorbell_history_screen.dart';
import 'screens/active_call_screen.dart';
import 'screens/qr_scan_screen.dart';
import 'screens/root_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_navigation.dart';
import 'services/appearance.dart';
import 'services/sip_channel.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind transparent status/navigation bars (Android 15 does this
  // anyway); NwSystemUi sets their icon colours per theme.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  LicenseRegistry.addLicense(_fontLicenses);
  runApp(const HAPhoneApp());
}

/// SIL OFL of the bundled fonts, shown in the licence page.
Stream<LicenseEntry> _fontLicenses() async* {
  for (final (package, file) in [
    ('Bricolage Grotesque', 'assets/fonts/BricolageGrotesque-OFL.txt'),
    ('Manrope', 'assets/fonts/Manrope-OFL.txt'),
  ]) {
    yield LicenseEntryWithLineBreaks([package], await rootBundle.loadString(file));
  }
}

class HAPhoneApp extends StatefulWidget {
  const HAPhoneApp({super.key, this.appearance});

  /// In-app "Erscheinungsbild" (default Dunkel); injectable for tests.
  final AppearanceController? appearance;

  @override
  State<HAPhoneApp> createState() => _HAPhoneAppState();
}

class _HAPhoneAppState extends State<HAPhoneApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  AppearanceController get _appearance => widget.appearance ?? AppearanceController.instance;

  @override
  void initState() {
    super.initState();
    // Stored choice + one push to native (ringing screen reads it there).
    unawaited(_appearance.load());
    // Native -> Dart hand-off, e.g. IncomingCallActivity's post-answer
    // navigation (see SipChannel.setNavigationHandler / MainActivity.kt).
    SipChannel.instance.setNavigationHandler(_handleNativeRoute);
  }

  void _handleNativeRoute(String route) {
    if (route.startsWith('provision:')) {
      _navigatorKey.currentState?.push(MaterialPageRoute<void>(
        builder: (_) => QrScanScreen(initialLink: route.substring('provision:'.length)),
      ));
      return;
    }
    if (route == 'doorbell') {
      // "Es hat geklingelt" notification (DoorbellMissedNotifier.kt).
      _navigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => const DoorbellHistoryScreen()));
      return;
    }
    if (route == 'active_call') {
      _navigatorKey.currentState?.pushNamedAndRemoveUntil('/active-call', (r) => r.isFirst);
      return;
    }
    // Voicemail/missed-call notifications: back to the tabs, Verlauf with the matching filter.
    if (AppNavigation.instance.handleRoute(route)) {
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppAppearance>(
      valueListenable: _appearance,
      builder: (context, appearance, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'HA-Phone',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: appearance.themeMode,
        debugShowCheckedModeBanner: false,
        // Inside the themed subtree: the bars follow the effective theme.
        builder: (context, child) => NwSystemUi(child: child ?? const SizedBox.shrink()),
        initialRoute: '/',
        routes: {
          '/': (_) => const RootScreen(),
          '/settings': (_) => const SettingsScreen(),
          '/active-call': (_) => const ActiveCallScreen(),
          '/qr-scan': (_) => const QrScanScreen(),
        },
      ),
    );
  }
}
