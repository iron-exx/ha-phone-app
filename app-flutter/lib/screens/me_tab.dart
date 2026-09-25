import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/appearance.dart';
import '../services/call_events.dart';
import '../services/directory_repository.dart';
import '../services/forwarding_repository.dart';
import '../services/pairing_reset.dart';
import '../services/presence_repository.dart';
import '../services/reachability_repository.dart';
import '../services/recordings_repository.dart';
import '../services/ring_settings_repository.dart';
import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/recording_ui.dart';
import '../utils/registration_ui.dart';
import '../widgets/appearance_sheet.dart';
import '../widgets/nw_widgets.dart';
import '../widgets/status_panel.dart';
import 'diagnostics_screen.dart';
import 'forwarding_screen.dart';
import 'reachability_screen.dart';
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
    PresenceRepository? presence,
    ForwardingRepository? forwarding,
    RingSettingsRepository? ring,
    ReachabilityRepository? reachability,
    AppearanceController? appearance,
  })  : _appearance = appearance,
        _recordings = recordings,
        _directory = directory,
        _presence = presence,
        _forwarding = forwarding,
        _ring = ring,
        _reachability = reachability;

  /// Called after returning from QR pairing or settings.
  final Future<void> Function() onSetupChanged;

  /// Called after the device was unpaired (back to onboarding).
  final Future<void> Function() onUnpaired;

  /// The tab is on screen (refreshes the recordings).
  final bool isActive;
  final RecordingsRepository? _recordings;
  final DirectoryRepository? _directory;
  final PresenceRepository? _presence;
  final ForwardingRepository? _forwarding;
  final RingSettingsRepository? _ring;
  final ReachabilityRepository? _reachability;
  final AppearanceController? _appearance;

  @override
  State<MeTab> createState() => _MeTabState();
}

class _MeTabState extends State<MeTab> {
  RegistrationUi _registration = RegistrationUi.connecting;
  StreamSubscription<CallEvent>? _events;

  RecordingsRepository get _recordings => widget._recordings ?? RecordingsRepository.instance;
  DirectoryRepository get _dir => widget._directory ?? DirectoryRepository.instance;
  ReachabilityRepository get _reach => widget._reachability ?? ReachabilityRepository.instance;
  AppearanceController get _appearance => widget._appearance ?? AppearanceController.instance;

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
    // After the frame: refresh() notifies at once, and other tabs (Verlauf)
    // listen to the same repository.
    if (widget.isActive && !oldWidget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_recordings.refresh());
          unawaited(_reach.refresh());
        }
      });
    }
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
            style: FilledButton.styleFrom(backgroundColor: ctx.nw.endStrong, foregroundColor: ctx.nw.endInk),
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
    await resetForPairing(recordings: _recordings);
    await widget.onUnpaired();
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const PageHeader('Ich'),
            StatusPanel(
              directory: widget._directory,
              presence: widget._presence,
              forwarding: widget._forwarding,
              ring: widget._ring,
              onOpenForwarding: () => _push(ForwardingScreen(
                repository: widget._forwarding,
                directory: widget._directory,
                presence: widget._presence,
              )),
            ),
            const SectionHeader('Einstellungen'),
            _group([
              _reachabilityTile(),
              _recordingsTile(),
              _tile(
                icon: Icons.phone_forwarded_outlined,
                title: 'Weiterleitungen',
                subtitle: 'Was mit Anrufen passiert, je nach Status',
                onTap: () => _push(const ForwardingScreen()),
              ),
              _appearanceTile(),
              _tile(
                icon: Icons.monitor_heart_outlined,
                title: 'Diagnose',
                onTap: () => _push(const DiagnosticsScreen()),
              ),
              _tile(icon: Icons.settings_outlined, title: 'SIP-Einstellungen', onTap: () => _open('/settings')),
            ]),
            const SectionHeader('Gerät'),
            _group([
              _registrationTile(context),
              _tile(icon: Icons.refresh, title: 'Neu verbinden', onTap: _reconnect, chevron: false),
              _tile(icon: Icons.qr_code_scanner, title: 'Neu koppeln (QR-Code)', onTap: () => _open('/qr-scan')),
              _tile(
                icon: Icons.link_off,
                title: 'Gerät entkoppeln',
                color: c.end,
                onTap: _confirmUnpair,
                chevron: false,
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Text(
                'HA-Phone App $kAppVersion',
                textAlign: TextAlign.center,
                style: NwType.meta.copyWith(color: c.faint),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'HA-Phone',
                  applicationVersion: kAppVersion,
                ),
                child: const Text('Lizenzen'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Rows of one settings group inside a card, separated by hairlines.
  Widget _group(List<Widget> rows) {
    final c = context.nw;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: NwCard(
        padding: EdgeInsets.zero,
        radius: 20,
        clip: true,
        child: Column(
          children: [
            for (final (i, r) in rows.indexed) ...[
              if (i > 0) Divider(height: 1, indent: 56, color: c.stroke),
              r,
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? color,
    bool chevron = true,
    Key? key,
  }) {
    final c = context.nw;
    return ListTile(
      key: key,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: color ?? c.blue),
      title: Text(title, style: color == null ? null : TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: chevron ? Icon(Icons.chevron_right, color: c.faint) : null,
      onTap: onTap,
    );
  }

  /// "Erscheinungsbild" with the current choice; opens the small sheet.
  Widget _appearanceTile() {
    return ValueListenableBuilder<AppAppearance>(
      valueListenable: _appearance,
      builder: (context, current, _) => _tile(
        key: const Key('me-appearance'),
        icon: Icons.contrast,
        title: 'Erscheinungsbild',
        subtitle: current.label,
        onTap: () => AppearanceSheet.show(context, _appearance),
      ),
    );
  }

  /// "Erreichbarkeit" with an amber dot while a check fails.
  Widget _reachabilityTile() {
    final c = context.nw;
    return ListenableBuilder(
      listenable: _reach,
      builder: (context, _) {
        final problems = _reach.hasProblems;
        return ListTile(
          key: const Key('me-reachability'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Icon(Icons.verified_user_outlined, color: problems ? c.door : c.blue),
          title: const Text('Erreichbarkeit'),
          subtitle: Text(problems ? 'Nicht alles in Ordnung – bitte prüfen' : 'Klingelt das Handy zuverlässig?'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (problems)
                Container(
                  key: const Key('me-reach-dot'),
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: c.door, shape: BoxShape.circle),
                ),
              Icon(Icons.chevron_right, color: c.faint),
            ],
          ),
          onTap: () => _push(ReachabilityScreen(repository: widget._reachability)),
        );
      },
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
        return _tile(
          key: const Key('me-recordings'),
          icon: Icons.mic_none,
          title: 'Aufnahmen',
          subtitle: _recordings.hasLoaded ? recordingCountText(list.length) : 'Aufgezeichnete Gespräche',
          onTap: () => _push(RecordingsScreen(repository: widget._recordings, directory: widget._directory)),
        );
      },
    );
  }

  Widget _registrationTile(BuildContext context) {
    final c = context.nw;
    final color = switch (_registration) {
      RegistrationUi.online => c.answer,
      RegistrationUi.offline => c.end,
      RegistrationUi.connecting => c.door,
    };
    final icon = switch (_registration) {
      RegistrationUi.online => Icons.check_circle,
      RegistrationUi.offline => Icons.error_outline,
      RegistrationUi.connecting => Icons.sync,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: color),
      title: const Text('Verbindung zur Anlage'),
      subtitle: Text(_registration.label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}
