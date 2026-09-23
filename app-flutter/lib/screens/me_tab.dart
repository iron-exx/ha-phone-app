import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../models/presence.dart';
import '../services/call_events.dart';
import '../services/directory_repository.dart';
import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../utils/registration_ui.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/presence_chip.dart';

/// Ich tab: own extension, live registration state, device actions.
class MeTab extends StatefulWidget {
  const MeTab({super.key, required this.onSetupChanged, required this.onUnpaired});

  /// Called after returning from QR pairing or settings.
  final Future<void> Function() onSetupChanged;

  /// Called after the device was unpaired (back to onboarding).
  final Future<void> Function() onUnpaired;

  @override
  State<MeTab> createState() => _MeTabState();
}

class _MeTabState extends State<MeTab> {
  RegistrationUi _registration = RegistrationUi.connecting;
  StreamSubscription<CallEvent>? _events;

  @override
  void initState() {
    super.initState();
    _events = CallEvents.instance.stream.listen((e) {
      if (e is RegistrationStateEvent && mounted) {
        setState(() => _registration = RegistrationUi.fromState(e.state));
      }
    });
    _loadRegistration();
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _loadRegistration() async {
    try {
      final state = await SipChannel.instance.getRegistrationState();
      if (mounted) setState(() => _registration = RegistrationUi.fromState(state));
    } catch (e) {
      debugPrint('getRegistrationState failed: $e');
    }
  }

  Future<void> _reconnect() async {
    setState(() => _registration = RegistrationUi.connecting);
    try {
      await SipChannel.instance.register();
    } catch (e) {
      debugPrint('register failed: $e');
      if (mounted) setState(() => _registration = RegistrationUi.offline);
    }
  }

  Future<void> _open(String route) async {
    await Navigator.of(context).pushNamed(route);
    await widget.onSetupChanged();
    await _loadRegistration();
  }

  Future<void> _confirmUnpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gerät entkoppeln?'),
        content: const Text(
          'Die Zugangsdaten werden von diesem Handy gelöscht. Danach ist es nicht mehr '
          'erreichbar, bis es per QR-Code neu gekoppelt wird.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.hangup),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entkoppeln'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SipChannel.instance.unregister();
    } catch (e) {
      debugPrint('unregister failed: $e');
    }
    try {
      await SipChannel.instance.clearCredentials();
    } catch (e) {
      debugPrint('clearCredentials failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entkoppeln fehlgeschlagen – bitte erneut versuchen.')),
        );
      }
      return;
    }
    // No clearDeviceAuth in the contract; overwrite with empty values.
    try {
      await SipChannel.instance.saveDeviceAuth(apiHost: '', deviceId: '', deviceToken: '');
    } catch (e) {
      debugPrint('clearing device auth failed: $e');
    }
    await DirectoryRepository.instance.clear();
    await widget.onUnpaired();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ich')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListenableBuilder(
            listenable: DirectoryRepository.instance,
            builder: (context, _) => _ownExtension(context),
          ),
          const Divider(height: 32),
          _registrationTile(context),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Neu verbinden'),
            onTap: _reconnect,
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Einstellungen'),
            onTap: () => _open('/settings'),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Neu koppeln (QR-Code)'),
            onTap: () => _open('/qr-scan'),
          ),
          ListTile(
            leading: const Icon(Icons.link_off, color: AppColors.hangup),
            title: const Text('Gerät entkoppeln', style: TextStyle(color: AppColors.hangup)),
            onTap: _confirmUnpair,
          ),
          const Divider(height: 32),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('App-Version'),
            trailing: Text(kAppVersion),
          ),
        ],
      ),
    );
  }

  Widget _ownExtension(BuildContext context) {
    final theme = Theme.of(context);
    final self = DirectoryRepository.instance.directory?.self;
    final presence = self?.presence ?? Presence.unknown;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ContactAvatar(name: self?.name ?? '', number: self?.number ?? '', presence: presence, size: 64),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(self?.displayName ?? 'Eigene Nebenstelle', style: theme.textTheme.titleLarge),
                Text(
                  self == null ? 'Noch nicht geladen' : 'Nebenstelle ${self.number}',
                  style: tabular(theme.textTheme.bodyMedium),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    PresenceChip(presence: presence),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Status ändern folgt',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _registrationTile(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.circle, size: 14, color: _registration.color),
      title: const Text('Verbindung zur Anlage'),
      subtitle: Text(_registration.label, style: TextStyle(color: _registration.color)),
    );
  }
}
