import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/call_events.dart';
import '../services/call_history_store.dart';
import '../services/directory_repository.dart';
import '../services/forwarding_repository.dart';
import '../services/presence_repository.dart';
import '../services/recordings_repository.dart';
import '../services/sip_channel.dart';
import '../services/voicemail_repository.dart';
import '../theme/app_colors.dart';
import '../utils/recording_ui.dart';
import '../utils/registration_ui.dart';
import '../widgets/own_status_header.dart';
import 'diagnostics_screen.dart';
import 'forwarding_screen.dart';
import 'recordings_screen.dart';

/// Ich tab: Status (own extension, presence, registration), Einstellungen
/// (Aufnahmen, Weiterleitungen, Diagnose, SIP) and Gerät (reconnect,
/// re-pair, unpair). "Aufnahmen" only appears while recording is allowed or
/// recordings exist; the list is re-checked whenever the tab opens.
class MeTab extends StatefulWidget {
  const MeTab({
    super.key,
    required this.onSetupChanged,
    required this.onUnpaired,
    this.isActive = false,
    RecordingsRepository? recordings,
    DirectoryRepository? directory,
  })  : _recordings = recordings,
        _directory = directory;

  /// Called after returning from QR pairing or settings.
  final Future<void> Function() onSetupChanged;

  /// Called after the device was unpaired (back to onboarding).
  final Future<void> Function() onUnpaired;

  /// The tab is on screen (refreshes the recordings).
  final bool isActive;
  final RecordingsRepository? _recordings;
  final DirectoryRepository? _directory;

  @override
  State<MeTab> createState() => _MeTabState();
}

class _MeTabState extends State<MeTab> {
  RegistrationUi _registration = RegistrationUi.connecting;
  StreamSubscription<CallEvent>? _events;

  RecordingsRepository get _recordings => widget._recordings ?? RecordingsRepository.instance;
  DirectoryRepository get _dir => widget._directory ?? DirectoryRepository.instance;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_recordings.refresh());
      });
    }
    _events = CallEvents.instance.stream.listen((e) {
      if (e is RegistrationStateEvent && mounted) {
        setState(() => _registration = RegistrationUi.fromState(e.state));
      }
    });
    _loadRegistration();
  }

  @override
  void didUpdateWidget(MeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) unawaited(_recordings.refresh());
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
    PresenceRepository.instance.clear();
    ForwardingRepository.instance.clear();
    await CallHistoryStore.instance.clearPbx();
    await VoicemailRepository.instance.clear();
    _recordings.clear();
    await widget.onUnpaired();
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ich')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionHeader('Status'),
          const OwnStatusHeader(),
          _registrationTile(context),
          const Divider(height: 24),
          const _SectionHeader('Einstellungen'),
          _recordingsTile(),
          ListTile(
            leading: const Icon(Icons.phone_forwarded_outlined),
            title: const Text('Weiterleitungen'),
            subtitle: const Text('Was mit Anrufen passiert, je nach Status'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _push(const ForwardingScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Diagnose'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _push(const DiagnosticsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('SIP-Einstellungen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open('/settings'),
          ),
          const Divider(height: 24),
          const _SectionHeader('Gerät'),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Neu verbinden'),
            onTap: _reconnect,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Text(
              'HA-Phone App $kAppVersion',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shown while recording is allowed (directory or list) or recordings exist.
  Widget _recordingsTile() {
    return ListenableBuilder(
      listenable: Listenable.merge([_recordings, _dir]),
      builder: (context, _) {
        final list = _recordings.recordings;
        final allowed = (_dir.directory?.recordingAllowed ?? false) || _recordings.isAllowed;
        if (!allowed && list.isEmpty) return const SizedBox.shrink();
        return ListTile(
          key: const Key('me-recordings'),
          leading: const Icon(Icons.mic_none),
          title: const Text('Aufnahmen'),
          subtitle: Text(_recordings.hasLoaded ? recordingCountText(list.length) : 'Aufgezeichnete Gespräche'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(RecordingsScreen(repository: widget._recordings, directory: widget._directory)),
        );
      },
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}
