import 'dart:async';

import 'package:flutter/material.dart';

import '../models/reachability.dart';
import '../models/tailnet_status.dart';
import '../services/api_client.dart';
import '../services/directory_repository.dart';
import '../services/diagnostics_service.dart';
import '../services/reachability_repository.dart';
import '../services/reachability_service.dart';
import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/reach_checks.dart';
import '../widgets/nw_widgets.dart';

/// "Erreichbarkeit" (mockup Erreichbarkeit.dc.html): summary card (green when
/// everything passes, amber otherwise), one row per check with "Beheben",
/// OEM-specific advice. Re-checks when the user comes back from a settings page.
class ReachabilityScreen extends StatefulWidget {
  const ReachabilityScreen({
    super.key,
    ReachabilityRepository? repository,
    ReachabilityService? service,
    this.rttLoader,
    this.reconnect,
    this.testCall,
    this.testCallAvailable,
    this.tailnetStatus,
    this.tailnetStart,
  })  : _repository = repository,
        _service = service;

  final ReachabilityRepository? _repository;
  final ReachabilityService? _service;

  /// Response time of the PBX in ms (default: [DiagnosticsService.ping]).
  final Future<int?> Function()? rttLoader;

  /// Register again (default: [SipChannel.register]).
  final Future<void> Function()? reconnect;

  /// Ask the PBX for a test call (default: [ApiClient.requestTestCall]).
  final Future<void> Function()? testCall;

  /// Whether the PBX offers it (default: directory `self.test_call`).
  final bool? testCallAvailable;

  /// Tailscale tunnel state (default: [SipChannel.tailscaleStatus]).
  final Future<TailnetStatus> Function()? tailnetStatus;

  /// Join / reconnect the tailnet (default: [SipChannel.tailscaleStart]).
  final Future<String> Function()? tailnetStart;

  @override
  State<ReachabilityScreen> createState() => _ReachabilityScreenState();
}

class _ReachabilityScreenState extends State<ReachabilityScreen> with WidgetsBindingObserver {
  ReachabilityRepository get _repo => widget._repository ?? ReachabilityRepository.instance;
  ReachabilityService get _service => widget._service ?? ReachabilityService.instance;
  int? _rtt;
  bool _testCallBusy = false;
  String? _testCallInfo;
  TailnetStatus _tailnet = TailnetStatus.off;
  Timer? _tailnetPoll;

  bool get _canTestCall =>
      widget.testCallAvailable ?? (DirectoryRepository.instance.directory?.testCallAvailable ?? false);

  Future<void> _requestTestCall() async {
    setState(() {
      _testCallBusy = true;
      _testCallInfo = null;
    });
    String info;
    try {
      await (widget.testCall ??
          () async => ApiClient().requestTestCall(await DirectoryRepository.loadAuthFromNative()))();
      info = 'Die Anlage ruft dieses Handy in 10 Sekunden an. Sperr es ruhig.';
    } on ApiException catch (e) {
      info = testCallErrorText(e);
    } catch (_) {
      info = 'Anlage nicht erreichbar.';
    }
    if (!mounted) return;
    setState(() {
      _testCallBusy = false;
      _testCallInfo = info;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _tailnetPoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from a system settings page.
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final ring = _repo.ring;
    await Future.wait([
      _repo.refresh(),
      if (!ring.hasLoaded) ring.load(),
      _loadRtt(),
      _loadTailnet(),
    ]);
  }

  Future<void> _loadTailnet() async {
    TailnetStatus st;
    try {
      st = await (widget.tailnetStatus ?? SipChannel.instance.tailscaleStatus)();
    } catch (_) {
      st = TailnetStatus.off;
    }
    if (!mounted) return;
    setState(() => _tailnet = st);
    // While it is connecting / waiting for the login, follow it.
    _tailnetPoll?.cancel();
    if (st.configured && !st.running) {
      _tailnetPoll = Timer(const Duration(seconds: 3), () {
        if (mounted) unawaited(_loadTailnet());
      });
    }
  }

  Future<void> _startTailnet() async {
    try {
      await (widget.tailnetStart ?? SipChannel.instance.tailscaleStart)();
    } catch (e) {
      debugPrint('tailscale start failed: $e');
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted) await _loadTailnet();
  }

  Future<void> _loadRtt() async {
    final rtt = await (widget.rttLoader ?? DiagnosticsService().ping)();
    if (mounted) setState(() => _rtt = rtt);
  }

  Future<void> _fix(ReachCheck check) async {
    switch (check.fix) {
      case ReachFix.settings:
        final page = check.settingsPage;
        if (page != null) await _service.openSettings(page);
      case ReachFix.reconnect:
        try {
          await (widget.reconnect ?? SipChannel.instance.register)();
        } catch (e) {
          debugPrint('register failed: $e');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) await _refresh();
      case ReachFix.ringOn:
        final ring = _repo.ring;
        try {
          await ring.update(ring.settings.ringing());
        } catch (e) {
          debugPrint('ring on failed: $e');
        }
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return Scaffold(
      appBar: AppBar(),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          final s = _repo.snapshot;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const PageHeader('Erreichbarkeit'),
                if (s == null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: _repo.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : Text('Der Zustand des Handys lässt sich gerade nicht lesen.',
                            style: NwType.meta.copyWith(color: c.muted)),
                  )
                else
                  ..._content(context, s),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _content(BuildContext context, ReachabilitySnapshot s) {
    final ring = _repo.ring;
    final checks = buildReachChecks(s, ring.settings, ring.now(), rttMillis: _rtt);
    final summary = summarize(checks);
    final advice = oemAdviceFor(s.oemFamily);
    return [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: _summaryCard(context, summary)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Column(
          children: [
            for (final (i, check) in checks.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              _checkRow(context, check),
            ],
          ],
        ),
      ),
      if (_tailnet.configured)
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: _tailnetRow(context, describeTailnet(_tailnet))),
      if (advice != null) Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 0), child: _oemCard(context, advice)),
      if (_canTestCall) Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 0), child: _testCallBlock(context)),
    ];
  }

  Widget _testCallBlock(BuildContext context) {
    final c = context.nw;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('reach-test-call'),
          onPressed: _testCallBusy ? null : _requestTestCall,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: c.blue,
            foregroundColor: c.blueInk,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          icon: _testCallBusy
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.blueInk))
              : const Icon(Icons.call_outlined),
          label: const Text('Test-Anruf an mich'),
        ),
        const SizedBox(height: 8),
        Text(
          _testCallInfo ?? 'Die Anlage ruft dieses Handy nach 10 Sekunden an. So prüfst du das Klingeln bei gesperrtem Handy.',
          key: const Key('reach-test-call-info'),
          textAlign: TextAlign.center,
          style: NwType.meta.copyWith(color: c.faint),
        ),
      ],
    );
  }

  Widget _summaryCard(BuildContext context, ReachSummary summary) {
    final c = context.nw;
    final ok = summary.allOk;
    final fg = ok ? c.okText : c.door;
    return Container(
      key: Key(ok ? 'reach-summary-ok' : 'reach-summary-warn'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ok ? c.okSurface : c.doorSoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ok ? c.okStroke : c.door.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.verified_user_outlined : Icons.shield_outlined, size: 40, color: fg),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary.title, style: NwType.display(20).copyWith(color: c.text)),
                const SizedBox(height: 4),
                Text(summary.text,
                    key: const Key('reach-summary-text'), style: NwType.meta.copyWith(color: fg, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _icon(ReachCheckId id) => switch (id) {
        ReachCheckId.notifications => Icons.notifications_outlined,
        ReachCheckId.fullScreen => Icons.smartphone_outlined,
        ReachCheckId.battery => Icons.battery_charging_full_outlined,
        ReachCheckId.exactAlarm => Icons.alarm_outlined,
        ReachCheckId.connection => Icons.wifi_rounded,
        ReachCheckId.ringing => Icons.notifications_active_outlined,
      };

  Widget _checkRow(BuildContext context, ReachCheck check) {
    final c = context.nw;
    final color = check.ok ? c.answer : c.door;
    return Container(
      key: ValueKey('reach-${check.id.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: check.ok ? c.stroke : c.door.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(13)),
            child: Icon(_icon(check.id), size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.label, style: NwType.rowTitle.copyWith(color: c.text, fontWeight: FontWeight.w800, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(check.detail, style: NwType.meta.copyWith(color: c.faint, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (check.ok)
            Semantics(
              label: 'in Ordnung',
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: c.answer, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, size: 16, color: c.ground),
              ),
            )
          else
            FilledButton(
              key: ValueKey('reach-fix-${check.id.name}'),
              style: FilledButton.styleFrom(
                backgroundColor: c.door,
                foregroundColor: c.doorInk,
                minimumSize: const Size(kMinTap, kMinTap),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: NwType.chip.copyWith(fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
              onPressed: () => _fix(check),
              child: const Text('Beheben'),
            ),
        ],
      ),
    );
  }

  Widget _tailnetRow(BuildContext context, TailnetRowText t) {
    final c = context.nw;
    final color = t.ok ? c.answer : c.door;
    return Container(
      key: const Key('reach-tailnet'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.ok ? c.stroke : c.door.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(13)),
            child: Icon(Icons.public_rounded, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unterwegs erreichbar',
                    style: NwType.rowTitle.copyWith(color: c.text, fontWeight: FontWeight.w800, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(t.detail,
                    key: const Key('reach-tailnet-detail'), style: NwType.meta.copyWith(color: c.faint, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (t.action == null)
            Semantics(
              label: 'in Ordnung',
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: c.answer, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, size: 16, color: c.ground),
              ),
            )
          else
            FilledButton(
              key: const Key('reach-tailnet-action'),
              style: FilledButton.styleFrom(
                backgroundColor: c.door,
                foregroundColor: c.doorInk,
                minimumSize: const Size(kMinTap, kMinTap),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: NwType.chip.copyWith(fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
              onPressed: _startTailnet,
              child: Text(t.action!),
            ),
        ],
      ),
    );
  }

  Widget _oemCard(BuildContext context, OemAdvice advice) {
    final c = context.nw;
    return NwCard(
      key: const Key('reach-oem'),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates_outlined, color: c.blue),
              const SizedBox(width: 10),
              Expanded(child: Text(advice.title, style: NwType.rowTitle.copyWith(color: c.text, fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 6),
          Text('Dieser Hersteller beendet Apps im Hintergrund zusätzlich. Bitte einmal einstellen:',
              style: NwType.meta.copyWith(color: c.muted)),
          const SizedBox(height: 8),
          for (final (i, step) in advice.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}.', style: NwType.meta.copyWith(color: c.faint, fontWeight: FontWeight.w800)),
                  ),
                  Expanded(child: Text(step, style: NwType.meta.copyWith(color: c.text))),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('reach-oem-open'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('App-Einstellungen öffnen'),
              onPressed: () => _service.openSettings(ReachabilitySettingsPage.appDetails),
            ),
          ),
        ],
      ),
    );
  }
}


/// German text for a failed "Test-Anruf an mich" request.
String testCallErrorText(ApiException e) => switch (e.kind) {
      ApiErrorKind.unsupported => 'Die Anlage kann das erst ab HA-Phone 0.7.118.',
      ApiErrorKind.unauthorized => 'Gerät neu koppeln (QR-Code).',
      ApiErrorKind.unreachable => 'Anlage nicht erreichbar.',
      _ when e.statusCode == 429 => 'Ein Test läuft schon. Bitte eine Minute warten.',
      _ => 'Test-Anruf fehlgeschlagen.',
    };
