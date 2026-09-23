import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/call_events.dart';
import '../services/directory_repository.dart';
import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../utils/audio_route_ui.dart';
import '../utils/call_status.dart';
import '../widgets/audio_route_sheet.dart';
import '../widgets/call_header.dart';
import '../widgets/in_call_keypad_sheet.dart';
import '../widgets/round_action_button.dart';
import '../widgets/transfer_sheet.dart';

/// Linkus-style in-call screen: caller header, optional door-station video,
/// 3×2 action grid, big red hang-up button. Reached from any tab right after
/// placing a call, or from IncomingCallActivity's native "navigateTo:
/// active_call" hand-off after a real Answer tap.
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _muted = false;
  bool _onHold = false;
  bool _leaving = false;
  CurrentCall? _call;
  AudioRoutes? _routes;
  StreamSubscription<CallEvent>? _events;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final alreadyEnded = CallEvents.instance.lastDisconnected;
    if (alreadyEnded != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _leave(message: _endedMessage(alreadyEnded)),
      );
    }
    _events = CallEvents.instance.stream.listen(_onEvent);
    // Only the duration text changes every second; rebuilding is cheap.
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
    super.dispose();
  }

  void _onEvent(CallEvent event) {
    if (event is CallStateEvent) {
      if (event.state == 'disconnected') {
        _leave(message: _endedMessage(event));
      } else {
        _refreshCall();
      }
    } else if (event is AudioRouteEvent && mounted) {
      setState(() => _routes = event.routes);
    }
  }

  String _endedMessage(CallStateEvent e) {
    final reason = e.disconnectReason ?? '';
    return reason.isEmpty ? 'Anruf beendet' : 'Anruf beendet: $reason';
  }

  Future<void> _refreshCall() async {
    try {
      final call = await SipChannel.instance.getCurrentCall();
      if (mounted && call != null) {
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
    await SipChannel.instance.mute(next);
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _toggleHold() async {
    final next = !_onHold;
    await SipChannel.instance.hold(next);
    if (mounted) setState(() => _onHold = next);
  }

  Future<void> _endCall() async {
    try {
      await SipChannel.instance.hangup();
    } catch (e) {
      debugPrint('hangup failed: $e');
    }
    _leave();
  }

  Future<void> _openDoor() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SipChannel.instance.openDoor();
      messenger.showSnackBar(const SnackBar(content: Text('Tür-Code gesendet')));
    } catch (e) {
      debugPrint('openDoor failed: $e');
      messenger.showSnackBar(const SnackBar(content: Text('Tür-Code konnte nicht gesendet werden')));
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
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

  void _showTransfer() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => TransferSheet(
        onTransfer: (target) {
          SipChannel.instance.transfer(target);
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    final number = call?.number ?? '';
    final name = (call?.name.isNotEmpty ?? false) ? call!.name : DirectoryRepository.instance.nameFor(number);
    final showVideo = call?.video ?? false;
    return PopScope(
      // Leaving only via hang-up or call end, so the call can't get "lost".
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            // Short screens (or video) drop the big avatar so the grid and
            // hang-up button always fit without scrolling.
            builder: (context, constraints) => _body(
              name: name,
              number: number,
              call: call,
              showVideo: showVideo,
              compact: showVideo || constraints.maxHeight < 680,
            ),
          ),
        ),
      ),
    );
  }

  Widget _body({
    required String name,
    required String number,
    required CurrentCall? call,
    required bool showVideo,
    required bool compact,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          SizedBox(height: compact ? 8 : 40),
          CallHeader(
            name: name,
            number: number,
            status: callStatusText(call, DateTime.now(), onHold: _onHold),
            secure: call?.secure ?? false,
            isDoor: call?.isDoor ?? false,
            compact: compact,
          ),
          const SizedBox(height: 16),
          if (showVideo) const _RemoteVideo() else const Spacer(),
          const SizedBox(height: 16),
          _actionGrid(call),
          SizedBox(height: compact ? 16 : 32),
          CallButton(
            key: const Key('hangup'),
            color: AppColors.hangup,
            icon: Icons.call_end,
            tooltip: 'Auflegen',
            onPressed: _endCall,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _actionGrid(CurrentCall? call) {
    final routeType = _routes?.current?.type;
    final isDoor = call?.isDoor ?? false;
    final buttons = <Widget>[
      RoundActionButton(
        icon: _muted ? Icons.mic_off : Icons.mic,
        label: 'Stumm',
        active: _muted,
        onPressed: _toggleMute,
      ),
      RoundActionButton(icon: Icons.dialpad, label: 'Tastatur', onPressed: _showKeypad),
      RoundActionButton(
        icon: audioRouteIcon(routeType),
        label: audioRouteLabel(routeType),
        active: routeType != null && routeType != 'earpiece',
        onPressed: _routes == null || _routes!.routes.isEmpty ? null : _onAudioPressed,
      ),
      RoundActionButton(
        icon: _onHold ? Icons.play_arrow : Icons.pause,
        label: _onHold ? 'Fortsetzen' : 'Halten',
        active: _onHold,
        onPressed: _toggleHold,
      ),
      RoundActionButton(icon: Icons.phone_forwarded, label: 'Weiterleiten', onPressed: _showTransfer),
      if (isDoor)
        RoundActionButton(icon: Icons.door_front_door, label: 'Tür öffnen', onPressed: _openDoor)
      else
        // Visually disabled, but tappable so users learn it's coming.
        GestureDetector(
          onTap: () => ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Konferenz folgt'))),
          child: const RoundActionButton(icon: Icons.call_merge, label: 'Konferenz', onPressed: null),
        ),
    ];
    return Column(
      children: [
        for (var row = 0; row < 2; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final b in buttons.sublist(row * 3, row * 3 + 3)) Expanded(child: Center(child: b)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Native TextureView with the call's incoming video (door station).
class _RemoteVideo extends StatelessWidget {
  const _RemoteVideo();

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ColoredBox(
            color: Colors.black,
            child: defaultTargetPlatform == TargetPlatform.android
                ? const AndroidView(viewType: remoteVideoViewType)
                : const Center(child: Icon(Icons.videocam_off, color: Colors.white54)),
          ),
        ),
      ),
    );
  }
}
