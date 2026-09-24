import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/contact.dart';
import '../services/api_client.dart';
import '../services/call_events.dart';
import '../services/directory_repository.dart';
import '../services/door_opener.dart';
import '../services/presence_repository.dart';
import '../services/recordings_repository.dart';
import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/audio_route_ui.dart';
import '../utils/call_status.dart';
import '../utils/recording_ui.dart';
import '../widgets/audio_route_sheet.dart';
import '../widgets/call_controls.dart';
import '../widgets/call_video_card.dart';
import '../widgets/door_card.dart' show doorActionIcon;
import '../widgets/in_call_keypad_sheet.dart';
import '../widgets/in_call_more_sheet.dart';
import '../widgets/nw_widgets.dart';
import '../widgets/presence_avatar.dart';
import '../widgets/round_action_button.dart' show CallButton;
import '../widgets/second_call_card.dart';
import '../widgets/transfer_sheet.dart';

/// Nachtwache in-call screen (no tab bar). Normal call: held second line as
/// a compact card on top ("Tauschen"), 112 dp presence avatar, name, number
/// and duration, "Zusammenführen" only with two lines, 2×3 control grid
/// (Stumm · Lautsprecher · Halten · Tastatur · Weiterleiten · Mehr) and the
/// red 80 dp hang-up button. Door/video call: video card with name and REC
/// chip, grid Stumm · Lautsprecher · Tür öffnen · Tastatur · first Home
/// Assistant action · Mehr. The rest (Konferenz, Rückfrage, Aufnehmen,
/// Direkt weiterleiten, Audio-Ausgabe, Anruf-Info) is in the "Mehr" sheet.
///
/// Reached from any tab right after placing a call, or from
/// IncomingCallActivity's native "navigateTo: active_call" hand-off.
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({
    super.key,
    DirectoryRepository? directory,
    RecordingsRepository? recordings,
    PresenceRepository? presence,
    DoorOpener? doorOpener,
  })  : _directory = directory,
        _recordings = recordings,
        _presence = presence,
        _doorOpener = doorOpener;

  final DirectoryRepository? _directory;
  final RecordingsRepository? _recordings;
  final PresenceRepository? _presence;
  final DoorOpener? _doorOpener;

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _muted = false;
  bool _onHold = false;
  bool _leaving = false;
  bool _doorBusy = false;
  bool _doorOpened = false;
  CurrentCall? _call;
  AudioRoutes? _routes;
  StreamSubscription<CallEvent>? _events;
  Timer? _ticker;
  Timer? _doorOpenedTimer;

  DirectoryRepository get _dir => widget._directory ?? DirectoryRepository.instance;
  RecordingsRepository get _recordings => widget._recordings ?? RecordingsRepository.instance;
  PresenceRepository get _presence => widget._presence ?? PresenceRepository.instance;
  DoorOpener get _doorOpener => widget._doorOpener ?? DoorOpener.instance;

  @override
  void initState() {
    super.initState();
    final alreadyEnded = CallEvents.instance.lastDisconnected;
    if (alreadyEnded != null) _leaveIfNoCall(alreadyEnded);
    _events = CallEvents.instance.stream.listen(_onEvent);
    // Only the duration texts change every second; rebuilding is cheap.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _call?.connectedAt != null) setState(() {});
    });
    _refreshCall();
    _loadRoutes();
  }

  @override
  void dispose() {
    _events?.cancel();
    _ticker?.cancel();
    _doorOpenedTimer?.cancel();
    super.dispose();
  }

  void _onEvent(CallEvent event) {
    if (event is CallStateEvent) {
      if (event.state == 'disconnected') {
        _recordings.retainLines(const {});
        _leave(message: _endedMessage(event));
      } else {
        _refreshCall();
      }
    } else if (event is AudioRouteEvent && mounted) {
      setState(() => _routes = event.routes);
    }
  }

  /// A call ended before this screen subscribed. Only leave when the native
  /// side has no live call either -- the event may belong to an earlier call
  /// (answered incoming call, "Zurück" banner).
  Future<void> _leaveIfNoCall(CallStateEvent ended) async {
    CurrentCall? call;
    try {
      call = await SipChannel.instance.getCurrentCall();
    } catch (e) {
      debugPrint('getCurrentCall failed: $e');
    }
    if (call != null) {
      if (identical(CallEvents.instance.lastDisconnected, ended)) {
        CallEvents.instance.lastDisconnected = null;
      }
      return;
    }
    _leave(message: _endedMessage(ended));
  }

  String _endedMessage(CallStateEvent e) {
    final reason = e.disconnectReason ?? '';
    return reason.isEmpty ? 'Anruf beendet' : 'Anruf beendet: $reason';
  }

  Future<void> _refreshCall() async {
    try {
      final call = await SipChannel.instance.getCurrentCall();
      if (mounted && call != null) {
        // Ended lines drop out (the PBX stops their recording itself).
        _recordings.retainLines(lineKeysOf(call));
        setState(() {
          _call = call;
          _muted = call.muted;
          _onHold = call.onHold;
        });
      }
    } catch (e) {
      debugPrint('getCurrentCall failed: $e');
    }
  }

  Future<void> _loadRoutes() async {
    try {
      final routes = await SipChannel.instance.getAudioRoutes();
      if (mounted) setState(() => _routes = routes);
    } catch (e) {
      debugPrint('getAudioRoutes failed: $e');
    }
  }

  void _leave({String? message}) {
    if (!mounted || _leaving) return;
    _leaving = true;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    try {
      await SipChannel.instance.mute(next);
    } catch (e) {
      debugPrint('mute failed: $e');
      _snack(next ? 'Stummschalten fehlgeschlagen' : 'Mikrofon konnte nicht eingeschaltet werden');
      return;
    }
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _toggleHold() async {
    final next = !_onHold;
    try {
      await SipChannel.instance.hold(next);
    } catch (e) {
      debugPrint('hold failed: $e');
      _snack(next ? 'Halten fehlgeschlagen' : 'Fortsetzen fehlgeschlagen');
      return;
    }
    if (mounted) setState(() => _onHold = next);
  }

  Future<void> _endCall() async {
    HapticFeedback.mediumImpact();
    final hadSecondLine = _call?.other != null;
    try {
      await SipChannel.instance.hangup();
    } catch (e) {
      // The call may still be live: stay; its "disconnected" event leaves.
      debugPrint('hangup failed: $e');
      _snack('Auflegen fehlgeschlagen – bitte erneut versuchen');
      return;
    }
    // With two lines the other call stays up: stay here, the native "lineEnded"
    // event refreshes the screen. The last call's "disconnected" event leaves.
    if (!hadSecondLine) _leave();
  }

  Future<void> _transfer(String target) async {
    try {
      await SipChannel.instance.transfer(target);
    } catch (e) {
      debugPrint('transfer failed: $e');
      _snack('Weiterleiten an $target fehlgeschlagen');
    }
  }

  /// Directory entry of the party on screen (door webhook, door detection).
  Contact? _contactOf(CurrentCall? call) => call == null ? null : _dir.directory?.contactFor(call.number);

  bool _isDoor(CurrentCall? call) => (call?.isDoor ?? false) || (_contactOf(call)?.isDoorStation ?? false);

  /// "Tür öffnen": the PBX webhook when the door has one (`door_open_remote`),
  /// else (or if the webhook is missing/unreachable) the DTMF code.
  Future<void> _openDoor(CurrentCall call) async {
    if (_doorBusy) return;
    if (_contactOf(call)?.doorOpenRemote ?? false) {
      setState(() => _doorBusy = true);
      try {
        final result = await _doorOpener.open(call.number);
        if (result == DoorOpenResult.opened) {
          _showDoorOpened();
          return;
        }
      } on ApiException catch (e) {
        // With a DTMF code the call can still open the door.
        if (call.doorCode.isEmpty) {
          _snack('Tür nicht geöffnet: ${e.message}');
          return;
        }
      } on Exception catch (e) {
        debugPrint('door webhook failed: $e');
        if (call.doorCode.isEmpty) {
          _snack('Tür nicht geöffnet.');
          return;
        }
      } finally {
        if (mounted) setState(() => _doorBusy = false);
      }
    }
    if (call.doorCode.isEmpty) {
      _snack('Für diese Tür ist kein Öffnen eingerichtet.');
      return;
    }
    try {
      await SipChannel.instance.openDoor();
      _snack('Tür-Code gesendet');
    } catch (e) {
      debugPrint('openDoor failed: $e');
      _snack('Tür-Code konnte nicht gesendet werden');
    }
  }

  void _showDoorOpened() {
    doorOpenedHaptic();
    if (!mounted) return;
    setState(() => _doorOpened = true);
    _doorOpenedTimer?.cancel();
    _doorOpenedTimer = Timer(kDoorOpenedFeedback, () {
      if (mounted) setState(() => _doorOpened = false);
    });
  }

  Future<void> _runDoorAction(String number, int index, String label) async {
    try {
      await SipChannel.instance.runDoorAction(number, index);
      _snack('$label: erledigt');
    } on PlatformException catch (e) {
      _snack(e.message ?? '$label fehlgeschlagen');
    }
  }

  Future<void> _setRoute(AudioRoute route) async {
    try {
      await SipChannel.instance.setAudioRoute(route.id);
    } catch (e) {
      debugPrint('setAudioRoute failed: $e');
    }
    // AudioRouteEvent normally follows; reload in case it doesn't.
    await _loadRoutes();
  }

  void _onAudioPressed() {
    final routes = _routes;
    if (routes == null) return;
    if (!needsRoutePicker(routes)) {
      final target = toggleTarget(routes);
      if (target != null) _setRoute(target);
      return;
    }
    _showRoutePicker(routes);
  }

  void _showRoutePicker(AudioRoutes routes) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => AudioRouteSheet(
        routes: routes,
        onSelect: (r) {
          Navigator.of(sheetContext).pop();
          _setRoute(r);
        },
      ),
    );
  }

  void _showKeypad() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const InCallKeypadSheet(),
    );
  }

  /// Weiterleiten: blind (REFER) or, with [consult], call the target first
  /// and connect via "Verbinden" once they answered.
  void _showTransfer({bool consult = true}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => TransferSheet(
        title: consult ? 'Weiterleiten an' : 'Direkt weiterleiten an',
        onTransfer: (target) {
          Navigator.of(sheetContext).pop();
          _transfer(target);
        },
        onConsult: consult
            ? (target) {
                Navigator.of(sheetContext).pop();
                _placeSecondCall(target);
              }
            : null,
      ),
    );
  }

  void _showAddCall() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => TransferSheet(
        title: 'Anruf hinzufügen',
        actionLabel: 'Anrufen',
        actionIcon: Icons.call,
        onTransfer: (target) {
          Navigator.of(sheetContext).pop();
          _placeSecondCall(target);
        },
      ),
    );
  }

  Future<void> _placeSecondCall(String number) async {
    try {
      await SipChannel.instance.makeCall(number);
    } catch (e) {
      debugPrint('second call failed: $e');
      _snack('Zweiter Anruf nicht möglich');
    }
    await _refreshCall();
  }

  Future<void> _runSecondLine(Future<bool> Function() action, String failure) async {
    try {
      if (!await action()) _snack(failure);
    } catch (e) {
      debugPrint('$failure: $e');
      _snack(failure);
    }
    await _refreshCall();
  }

  void _merge() => _runSecondLine(SipChannel.instance.mergeCalls, 'Konferenz erst möglich, wenn beide angenommen haben');

  /// Starts/stops the recording of the line on screen ([line] = its remote party).
  Future<void> _toggleRecording(CurrentCall line) async {
    final key = lineKeyOf(line);
    final starting = _recordings.recordingSince(key) == null;
    try {
      if (starting) {
        await _recordings.start(lineKey: key, peer: line.number);
      } else {
        await _recordings.stop(lineKey: key, peer: line.number);
      }
    } on ApiException catch (e) {
      _snack(recordingErrorText(e, starting: starting));
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _nameOf(CurrentCall? call) {
    final number = call?.number ?? '';
    return (call?.name.isNotEmpty ?? false) ? call!.name : _dir.nameFor(number);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Leaving only via hang-up or call end, so the call can't get "lost".
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([_dir, _recordings, _presence]),
            builder: (context, _) => LayoutBuilder(
              // Everything scrolls when large text or a small screen make it
              // taller than the screen; otherwise the grid sits at the bottom.
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(child: _body(constraints)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BoxConstraints constraints) {
    final call = _call;
    final isDoor = _isDoor(call);
    final videoMode = isDoor || (call?.video ?? false);
    final other = call?.other;
    final recordingSince = call == null ? null : _recordings.recordingSince(lineKeyOf(call));
    final rec = recordingSince == null ? null : RecChip(elapsed: DateTime.now().difference(recordingSince));
    final short = constraints.maxHeight < 640;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (other != null) ...[
            SecondCallCard(
              other: other,
              conference: call!.conference,
              directory: _dir,
              presence: avatarPresenceFor(_presence.statusFor(other.number)),
              onAnswerWaiting: () => _runSecondLine(SipChannel.instance.answerWaiting, 'Annehmen fehlgeschlagen'),
              onRejectWaiting: () async {
                await SipChannel.instance.rejectWaiting();
                await _refreshCall();
              },
              onSwap: () => _runSecondLine(SipChannel.instance.swapCalls, 'Makeln fehlgeschlagen'),
            ),
            const SizedBox(height: 12),
          ],
          if (videoMode)
            ..._videoHeader(call, isDoor: isDoor, rec: rec, constraints: constraints)
          else
            ..._caller(call, rec: rec, short: short || other != null),
          ..._lineChips(call),
          const Spacer(),
          const SizedBox(height: 16),
          CallControlGrid(
            columns: callGridColumns(context),
            children: isDoor ? _doorControls(call) : _normalControls(call),
          ),
          SizedBox(height: short ? 16 : 22),
          Center(
            child: Semantics(
              button: true,
              label: 'Auflegen',
              onTap: _endCall,
              excludeSemantics: true,
              child: CallButton(
                key: const Key('hangup'),
                color: context.nw.end,
                foreground: context.nw.endInk,
                icon: Icons.call_end,
                size: 80,
                tooltip: 'Auflegen',
                onPressed: _endCall,
              ),
            ),
          ),
          SizedBox(height: short ? 8 : 22),
        ],
      ),
    );
  }

  /// Normal call: big presence avatar, name, number · duration (+TLS), REC.
  List<Widget> _caller(CurrentCall? call, {required Widget? rec, required bool short}) {
    final c = context.nw;
    final number = call?.number ?? '';
    final name = _nameOf(call);
    final avatar = short ? 88.0 : 112.0;
    return [
      SizedBox(height: short ? 8 : 32),
      Center(
        child: PresenceAvatar(
          name: name,
          number: number,
          presence: avatarPresenceFor(_presence.statusFor(number)),
          size: avatar,
          background: c.blueSoft,
          foreground: c.blueOnSoft,
        ),
      ),
      const SizedBox(height: 18),
      Semantics(
        header: true,
        child: Text(
          name.isNotEmpty ? name : (number.isNotEmpty ? number : 'Verbinde…'),
          style: NwType.display(30).copyWith(color: c.text),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(height: 6),
      _statusLine(call, number: name.isNotEmpty ? number : ''),
      if (rec != null) ...[const SizedBox(height: 10), Center(child: rec)],
    ];
  }

  /// Door/video call: video card with name + REC chip, then name and duration.
  List<Widget> _videoHeader(
    CurrentCall? call, {
    required bool isDoor,
    required Widget? rec,
    required BoxConstraints constraints,
  }) {
    final c = context.nw;
    final name = _nameOf(call);
    final label = name.isNotEmpty ? name : (call?.number ?? '');
    final maxVideo = (constraints.maxWidth * 0.8).clamp(140.0, 300.0);
    final reserved = 440.0 + (call?.other != null ? 76 : 0);
    final height = (constraints.maxHeight - reserved).clamp(140.0, maxVideo);
    return [
      CallVideoCard(
        label: label,
        height: height,
        showVideo: call?.video ?? false,
        isDoor: isDoor,
        trailingChip: rec,
      ),
      const SizedBox(height: 16),
      Semantics(
        header: true,
        child: Text(
          label.isNotEmpty ? label : 'Verbinde…',
          style: NwType.display(26).copyWith(color: c.text),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(height: 4),
      _statusLine(call, number: isDoor ? 'Türstation' : ''),
    ];
  }

  /// "16 · 02:37 · 🔒 TLS" (wraps with large text).
  Widget _statusLine(CurrentCall? call, {required String number}) {
    final c = context.nw;
    final style = NwType.meta.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: c.muted);
    final secure = call?.secure ?? false;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        if (number.isNotEmpty) ...[
          Text(number, style: style),
          Text('·', style: style),
        ],
        Text(callStatusText(call, DateTime.now(), onHold: _onHold), key: const Key('call-status'), style: style),
        if (secure)
          Semantics(
            label: 'verschlüsselt (TLS)',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, size: 14, color: c.muted),
                const SizedBox(width: 2),
                Text('TLS', style: style.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    );
  }

  /// "Zusammenführen" + "Verbinden", only with a held second line.
  List<Widget> _lineChips(CurrentCall? call) {
    final other = call?.other;
    if (call == null || other == null || other.isWaiting || call.conference) return const [];
    return [
      const SizedBox(height: 10),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          NwChip(
            key: const Key('merge'),
            label: 'Zusammenführen',
            icon: Icons.call_merge,
            selected: true,
            semanticLabel: 'Zusammenführen zur Konferenz',
            onTap: _merge,
          ),
          NwChip(
            key: const Key('connect'),
            label: 'Verbinden',
            icon: Icons.call_split,
            semanticLabel: 'Beide Leitungen verbinden und selbst auflegen',
            onTap: () => _runSecondLine(SipChannel.instance.transferAttended, 'Verbinden fehlgeschlagen'),
          ),
        ],
      ),
    ];
  }

  CallControlButton _muteButton() => CallControlButton(
        key: const Key('mute'),
        icon: _muted ? Icons.mic_off : Icons.mic_off_outlined,
        label: 'Stumm',
        toggled: _muted,
        tone: _muted ? CallControlTone.active : CallControlTone.normal,
        onPressed: _toggleMute,
      );

  CallControlButton _audioButton() {
    final routes = _routes;
    final type = routes?.current?.type;
    final picker = routes != null && needsRoutePicker(routes);
    final on = type != null && type != 'earpiece';
    final current = routes?.current;
    return CallControlButton(
      key: const Key('audio'),
      icon: picker ? audioRouteIcon(type) : Icons.volume_up,
      label: picker ? 'Audio' : 'Lautsprecher',
      semanticLabel: picker ? 'Audio-Ausgabe: ${current == null ? '' : audioRouteName(current)}' : 'Lautsprecher',
      toggled: picker ? null : on,
      tone: on ? CallControlTone.active : CallControlTone.normal,
      onPressed: routes == null || routes.routes.isEmpty ? null : _onAudioPressed,
    );
  }

  CallControlButton _keypadButton() => CallControlButton(
        key: const Key('keypad'),
        icon: Icons.dialpad,
        label: 'Tastatur',
        onPressed: _showKeypad,
      );

  CallControlButton _transferButton() => CallControlButton(
        key: const Key('transfer'),
        icon: Icons.phone_forwarded,
        label: 'Weiterleiten',
        onPressed: _call == null ? null : _showTransfer,
      );

  CallControlButton _moreButton() => CallControlButton(
        key: const Key('more'),
        icon: Icons.more_horiz,
        label: 'Mehr',
        semanticLabel: 'Mehr Funktionen',
        onPressed: _showMore,
      );

  List<Widget> _normalControls(CurrentCall? call) => [
        _muteButton(),
        _audioButton(),
        CallControlButton(
          key: const Key('hold'),
          icon: _onHold ? Icons.play_arrow : Icons.pause,
          label: _onHold ? 'Fortsetzen' : 'Halten',
          toggled: _onHold,
          tone: _onHold ? CallControlTone.active : CallControlTone.normal,
          onPressed: _toggleHold,
        ),
        _keypadButton(),
        _transferButton(),
        _moreButton(),
      ];

  List<Widget> _doorControls(CurrentCall? call) {
    final actions = call?.doorActions ?? const <String>[];
    return [
      _muteButton(),
      _audioButton(),
      CallControlButton(
        key: const Key('door-open'),
        icon: _doorOpened ? Icons.check_rounded : Icons.door_front_door_outlined,
        label: _doorOpened ? 'Tür geöffnet ✓' : 'Tür öffnen',
        semanticLabel: _doorOpened ? 'Tür geöffnet' : 'Tür öffnen',
        tone: _doorOpened ? CallControlTone.done : CallControlTone.door,
        busy: _doorBusy,
        onPressed: call == null ? null : () => _openDoor(call),
      ),
      _keypadButton(),
      // First Home Assistant action of the door; without any, Weiterleiten.
      if (call != null && actions.isNotEmpty)
        CallControlButton(
          key: const Key('door-action-0'),
          icon: doorActionIcon(actions.first),
          label: actions.first,
          onPressed: () => _runDoorAction(call.number, 0, actions.first),
        )
      else
        _transferButton(),
      _moreButton(),
    ];
  }

  // ---------------------------------------------------------------- Mehr

  void _showMore() {
    final call = _call;
    final isDoor = _isDoor(call);
    final actions = call?.doorActions ?? const <String>[];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        void run(VoidCallback action) {
          Navigator.of(sheetContext).pop();
          action();
        }

        return InCallMoreSheet(
          tiles: _moreTiles(call, isDoor: isDoor, run: run),
          routes: _routes,
          onRoute: (r) => run(() => _setRoute(r)),
          doorActions: [
            if (call != null && isDoor)
              for (final (i, label) in actions.indexed)
                if (i > 0) (i, label),
          ],
          onDoorAction: call == null ? null : (i, label) => run(() => _runDoorAction(call.number, i, label)),
        );
      },
    );
  }

  List<MoreTile> _moreTiles(CurrentCall? call, {required bool isDoor, required void Function(VoidCallback) run}) {
    final c = context.nw;
    final other = call?.other;
    final canRecord = _dir.directory?.recordingAllowed ?? false;
    final recording = call != null && _recordings.recordingSince(lineKeyOf(call)) != null;
    final routes = _routes;
    final String? conferenceReason = switch ((call, other)) {
      (null, _) => 'Verbinde…',
      (final CurrentCall line, _) when line.conference => 'Läuft bereits',
      (_, null) => 'Erst Rückfrage starten',
      (_, final CurrentCall o) when o.isWaiting => 'Erst annehmen',
      _ => null,
    };
    return [
      MoreTile(
        key: const Key('more-conference'),
        label: 'Konferenz',
        icon: Icons.group_add_outlined,
        disabledReason: conferenceReason,
        onTap: conferenceReason == null ? () => run(_merge) : null,
      ),
      MoreTile(
        key: const Key('more-add-call'),
        label: 'Rückfrage',
        icon: Icons.add_call,
        semanticLabel: 'Rückfrage: zweiten Anruf starten',
        // One second line at most: waiting, held or conference partner.
        disabledReason: call == null ? 'Verbinde…' : (other != null ? 'Zweite Leitung belegt' : null),
        onTap: call != null && other == null ? () => run(_showAddCall) : null,
      ),
      if (canRecord)
        MoreTile(
          key: const Key('record'),
          label: recording ? 'Stopp' : 'Aufnehmen',
          semanticLabel: recording ? 'Aufnahme stoppen' : 'Gespräch aufnehmen',
          icon: recording ? Icons.stop_circle_outlined : Icons.radio_button_checked,
          iconColor: c.end,
          // Only an answered call can be recorded; one request at a time.
          disabledReason: call?.connectedAt == null
              ? 'Erst nach dem Annehmen'
              : (_recordings.isSwitching ? 'Einen Moment…' : null),
          onTap: call?.connectedAt == null || _recordings.isSwitching ? null : () => run(() => _toggleRecording(call!)),
        ),
      MoreTile(
        key: const Key('more-blind-transfer'),
        label: 'Direkt weiterleiten',
        icon: Icons.alt_route,
        disabledReason: call == null ? 'Verbinde…' : null,
        onTap: call == null ? null : () => run(() => _showTransfer(consult: false)),
      ),
      if (isDoor) ...[
        MoreTile(
          key: const Key('more-hold'),
          label: _onHold ? 'Fortsetzen' : 'Halten',
          icon: _onHold ? Icons.play_arrow : Icons.pause,
          onTap: () => run(_toggleHold),
        ),
        if ((call?.doorActions ?? const []).isNotEmpty)
          MoreTile(
            key: const Key('more-transfer'),
            label: 'Weiterleiten',
            icon: Icons.phone_forwarded,
            onTap: call == null ? null : () => run(_showTransfer),
          ),
      ],
      MoreTile(
        key: const Key('more-audio'),
        label: 'Audio-Ausgabe',
        icon: Icons.headphones_outlined,
        disabledReason: routes == null || routes.routes.isEmpty ? 'Nicht verfügbar' : null,
        onTap: routes == null || routes.routes.isEmpty ? null : () => run(() => _showRoutePicker(routes)),
      ),
      MoreTile(
        key: const Key('more-info'),
        label: 'Anruf-Info',
        icon: Icons.info_outline,
        onTap: () => run(_showCallInfo),
      ),
    ];
  }

  void _showCallInfo() {
    final call = _call;
    final name = _nameOf(call);
    final rows = <(String, String)>[
      ('Name', name.isNotEmpty ? name : '–'),
      ('Nummer', call?.number ?? '–'),
      ('Richtung', call?.direction == 'outgoing' ? 'ausgehend' : 'eingehend'),
      ('Status', callStatusText(call, DateTime.now(), onHold: _onHold)),
      ('Verbindung', (call?.secure ?? false) ? 'TLS-verschlüsselt' : 'unverschlüsselt'),
      ('Video', (call?.video ?? false) ? 'ja' : 'nein'),
      if (_isDoor(call)) ('Art', 'Türstation'),
      if (call?.other != null) ('Zweite Leitung', _nameOrNumber(call!.other!)),
      if (_routes?.current != null) ('Audio', audioRouteName(_routes!.current!)),
    ];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Anruf-Info'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: MergeSemantics(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        Text('$label:', style: NwType.meta.copyWith(color: dialogContext.nw.faint)),
                        Text(value, style: tabular(NwType.rowTitle)?.copyWith(color: dialogContext.nw.text)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Schließen')),
        ],
      ),
    );
  }

  String _nameOrNumber(CurrentCall line) {
    if (line.name.isNotEmpty) return line.name;
    final n = _dir.nameFor(line.number);
    return n.isNotEmpty ? '$n (${line.number})' : line.number;
  }
}
