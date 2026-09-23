import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/call_events.dart';
import '../services/directory_repository.dart';
import '../services/favorites_store.dart';
import '../services/provisioning_events.dart';
import '../services/sip_channel.dart';
import 'app_shell.dart';
import 'onboarding_screen.dart';

/// The '/' route: onboarding until SIP credentials exist, then the tab
/// shell. Replaces the old HomeScreen card UI.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  bool _checking = true;
  bool _provisioned = false;

  @override
  void initState() {
    super.initState();
    CallEvents.instance.start();
    unawaited(FavoritesStore.instance.load());
    provisioningRevision.addListener(_refresh);
    _refresh();
    // Fix: this request existed in the old native Compose MainActivity but
    // was dropped/never ported when MainActivity became a FlutterActivity
    // (Phase 1 port) -- without it, incoming-call push notifications are
    // silently suppressed on Android 13+.
    _requestPermissions();
  }

  @override
  void dispose() {
    provisioningRevision.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    try {
      await [Permission.notification, Permission.microphone].request();
    } catch (e) {
      debugPrint('permission request failed: $e');
    }
  }

  /// Re-reads the provisioning state; registers and loads the directory when
  /// provisioned. Called on start and after pairing/settings/unpairing.
  Future<void> _refresh() async {
    bool ok;
    try {
      ok = await SipChannel.instance.hasValidCredentials();
    } catch (e) {
      // Cold start: the pre-warmed engine can ask before MainActivity has registered the
      // channel. "Not provisioned" would be a lie here, so keep the spinner and ask again.
      debugPrint('hasValidCredentials failed, retrying: $e');
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) unawaited(_refresh());
      return;
    }
    if (ok) {
      SipChannel.instance.register().catchError((Object e) {
        debugPrint('SIP register failed: $e');
      });
      unawaited(DirectoryRepository.instance.init());
    }
    if (!mounted) return;
    setState(() {
      _provisioned = ok;
      _checking = false;
    });
  }

  Future<void> _openAndRefresh(String route) async {
    await Navigator.of(context).pushNamed(route);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_provisioned) {
      return OnboardingScreen(
        onScanQr: () => _openAndRefresh('/qr-scan'),
        onManualSetup: () => _openAndRefresh('/settings'),
      );
    }
    return AppShell(onSetupChanged: _refresh, onUnpaired: _refresh);
  }
}
