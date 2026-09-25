import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../services/call_events.dart';
import '../services/diagnostics_service.dart';
import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../utils/diagnostics_report.dart';
import '../utils/registration_ui.dart';

/// Ich → Diagnose: registration (live), SIP server, API host, app version,
/// PBX reachability and which features the PBX version offers. "Diagnose
/// kopieren" puts a plain-text summary without secrets on the clipboard.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, DiagnosticsService? service}) : _service = service;

  final DiagnosticsService? _service;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late final DiagnosticsService _service = widget._service ?? DiagnosticsService();
  RegistrationUi _registration = RegistrationUi.connecting;
  DiagnosticsInfo? _info;
  bool _probing = false;
  StreamSubscription<CallEvent>? _events;

  @override
  void initState() {
    super.initState();
    _events = CallEvents.instance.stream.listen((e) {
      if (e is RegistrationStateEvent && mounted) {
        setState(() {
          _registration = RegistrationUi.fromState(e.state);
          _info = _info?.copyWith(registration: _registration.label);
        });
      }
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<Map<String, String>> _safe(Future<Map<String, String>> Function() read) async {
    try {
      return await read();
    } catch (e) {
      debugPrint('diagnostics read failed: $e');
      return const {};
    }
  }

  Future<void> _load() async {
    try {
      _registration = RegistrationUi.fromState(await SipChannel.instance.getRegistrationState());
    } catch (e) {
      debugPrint('getRegistrationState failed: $e');
    }
    final credentials = await _safe(SipChannel.instance.getCredentials);
    final deviceAuth = await _safe(SipChannel.instance.getDeviceAuth);
    if (!mounted) return;
    setState(() {
      _info = DiagnosticsInfo.fromNative(
        appVersion: kAppVersion,
        registration: _registration.label,
        credentials: credentials,
        deviceAuth: deviceAuth,
      );
    });
    await _probe();
  }

  Future<void> _probe() async {
    if (_probing) return;
    setState(() => _probing = true);
    final result = await _service.probe();
    if (!mounted) return;
    setState(() {
      _probing = false;
      _info = _info?.copyWith(reachability: result.reachability, features: result.features);
    });
  }

  Future<void> _copy() async {
    final info = _info;
    if (info == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: info.toText()));
    messenger.showSnackBar(const SnackBar(content: Text('Diagnose kopiert.')));
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnose'),
        actions: [
          IconButton(
            tooltip: 'Erneut prüfen',
            icon: const Icon(Icons.refresh),
            onPressed: _probing ? null : _probe,
          ),
        ],
      ),
      body: info == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  leading: Icon(Icons.circle, size: 14, color: _registration.color),
                  title: const Text('Registrierung'),
                  subtitle: Text(_registration.label, style: TextStyle(color: _registration.color)),
                ),
                _tile(Icons.dns_outlined, 'SIP-Server', '${info.sipServer} · ${info.transport}'),
                _tile(Icons.dialpad, 'Nebenstelle', info.sipUser),
                _tile(Icons.lan_outlined, 'API-Host', info.apiHost),
                _tile(Icons.lock_outline, 'Verbindung zur Anlage', info.apiSecurity),
                _tile(Icons.info_outline, 'App-Version', info.appVersion),
                const Divider(height: 24),
                _reachabilityTile(info),
                _sectionHeader(context, 'Anlage-Version ausreichend'),
                if (_probing && info.features.isEmpty)
                  const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
                for (final f in info.features) _featureTile(f),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Diagnose kopieren'),
                    onPressed: _copy,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _tile(IconData icon, String title, String value) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(value, style: tabular(Theme.of(context).textTheme.bodyMedium)),
      );

  Widget _reachabilityTile(DiagnosticsInfo info) {
    final r = info.reachability;
    final ok = r?.millis != null;
    return ListTile(
      leading: Icon(
        ok ? Icons.check_circle_outline : Icons.error_outline,
        color: r == null ? null : (ok ? AppColors.presenceAvailable : AppColors.hangup),
      ),
      title: const Text('Anlage'),
      subtitle: Text(r?.text ?? (_probing ? 'wird geprüft …' : 'nicht geprüft')),
    );
  }

  Widget _featureTile(FeatureCheck f) {
    final color = switch (f.support) {
      FeatureSupport.supported => AppColors.presenceAvailable,
      FeatureSupport.unsupported => AppColors.presenceAway,
      FeatureSupport.unknown => AppColors.presenceOffline,
    };
    return ListTile(
      leading: Icon(
        f.support == FeatureSupport.supported ? Icons.check : Icons.warning_amber_outlined,
        color: color,
      ),
      title: Text(f.label),
      subtitle: Text(f.text),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            )),
      );
}
