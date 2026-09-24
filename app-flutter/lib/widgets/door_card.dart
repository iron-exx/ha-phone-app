import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/contact.dart';
import '../services/call_launcher.dart';
import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'nw_widgets.dart';

/// Icon for a Home Assistant door action by its label ("Licht", "Garage").
IconData doorActionIcon(String label) {
  final l = label.toLowerCase();
  if (l.contains('licht') || l.contains('lampe') || l.contains('light')) return Icons.lightbulb_outline;
  if (l.contains('garage')) return Icons.garage_outlined;
  if (l.contains('tor') || l.contains('gate')) return Icons.fence;
  if (l.contains('alarm')) return Icons.shield_outlined;
  if (l.contains('klingel') || l.contains('gong')) return Icons.notifications_off_outlined;
  return Icons.bolt;
}

/// Runs a door station's Home Assistant action on the PBX (works without a
/// call). Replaceable in tests.
typedef DoorActionRunner = Future<void> Function(String number, int index);

Future<void> _runOnPbx(String number, int index) => SipChannel.instance.runDoorAction(number, index);

/// Start card of a door station: picture area (placeholder until the PBX
/// keeps a last picture), name + last ring, and the amber main action.
/// Opening needs the DTMF code inside a call, so the main action calls the
/// door ("Tür anrufen", then "Tür öffnen" on the call screen); the door's
/// Home Assistant actions run directly as icon buttons.
class DoorCard extends StatefulWidget {
  const DoorCard({super.key, required this.door, this.lastRing, DoorActionRunner? runAction})
      : _runAction = runAction ?? _runOnPbx;

  final Contact door;

  /// Last call from this door (any device), null if unknown.
  final DateTime? lastRing;
  final DoorActionRunner _runAction;

  @override
  State<DoorCard> createState() => _DoorCardState();
}

class _DoorCardState extends State<DoorCard> {
  /// Index of the action that just succeeded (shows ✓ for 2 s).
  int? _done;
  int? _running;
  Timer? _doneTimer;

  @override
  void dispose() {
    _doneTimer?.cancel();
    super.dispose();
  }

  Future<void> _run(int index, String label) async {
    if (_running != null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _running = index);
    try {
      await widget._runAction(widget.door.number, index);
      HapticFeedback.heavyImpact();
      unawaited(Future<void>.delayed(const Duration(milliseconds: 120), HapticFeedback.heavyImpact));
      if (!mounted) return;
      setState(() => _done = index);
      _doneTimer?.cancel();
      _doneTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _done = null);
      });
      messenger.showSnackBar(SnackBar(content: Text('„$label“ ausgeführt')));
    } on PlatformException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message ?? '„$label“ fehlgeschlagen')));
    } catch (e) {
      debugPrint('runDoorAction failed: $e');
      messenger.showSnackBar(SnackBar(content: Text('„$label“ fehlgeschlagen')));
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final door = widget.door;
    final actions = door.doorActions;
    final shown = actions.length > 3 ? 3 : actions.length;
    return NwCard(
      key: ValueKey('door-card-${door.number}'),
      radius: 26,
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _picture(c),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: NwPillButton(
                    key: ValueKey('door-call-${door.number}'),
                    label: 'Tür anrufen',
                    icon: Icons.door_front_door_outlined,
                    background: c.door,
                    foreground: c.doorInk,
                    onPressed: () => CallLauncher.call(context, door.number),
                  ),
                ),
                for (var i = 0; i < shown; i++) ...[
                  const SizedBox(width: 10),
                  _actionButton(c, i, actions[i]),
                ],
                if (actions.length > shown) ...[
                  const SizedBox(width: 10),
                  _moreActions(c, shown),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _picture(NwColors c) {
    final last = widget.lastRing;
    final overlay = c.ground.withOpacity(0.72);
    return Container(
      height: 132,
      color: Color.alphaBlend(c.door.withOpacity(0.07), c.raised),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_outlined, size: 32, color: c.faint),
                const SizedBox(height: 6),
                Text('Live-Bild beim Klingeln', style: NwType.meta.copyWith(color: c.faint, fontSize: 12)),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            right: 110,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _overlayChip(
                overlay,
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.door_front_door_outlined, size: 14, color: c.door),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(widget.door.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: NwType.chip.copyWith(color: c.text, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ]),
              ),
            ),
          ),
          if (last != null)
            Positioned(
              right: 12,
              top: 12,
              child: _overlayChip(
                overlay,
                Text('zuletzt ${_clock(last)}', style: NwType.meta.copyWith(color: c.text, fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  static String _clock(DateTime t) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? '${two(t.hour)}:${two(t.minute)}' : '${two(t.day)}.${two(t.month)}.';
  }

  Widget _overlayChip(Color bg, Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
        child: child,
      );

  Widget _actionButton(NwColors c, int index, String label) {
    final done = _done == index;
    final running = _running == index;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: done ? '$label ausgeführt' : label,
        excludeSemantics: true,
        child: Material(
          key: ValueKey('door-action-${widget.door.number}-$index'),
          color: done ? c.okSurface : c.raised,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _run(index, label),
            child: SizedBox(
              width: 52,
              height: 52,
              child: running
                  ? Padding(padding: const EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2.5, color: c.text))
                  : Icon(done ? Icons.check_rounded : doorActionIcon(label), size: 20, color: done ? c.okText : c.text),
            ),
          ),
        ),
      ),
    );
  }

  Widget _moreActions(NwColors c, int from) {
    final actions = widget.door.doorActions;
    return PopupMenuButton<int>(
      tooltip: 'Weitere Aktionen',
      onSelected: (i) => _run(i, actions[i]),
      itemBuilder: (_) => [
        for (var i = from; i < actions.length; i++) PopupMenuItem(value: i, child: Text(actions[i])),
      ],
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(16)),
        child: Icon(Icons.more_horiz, color: c.text, size: 20),
      ),
    );
  }
}
