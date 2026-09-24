import 'dart:async';

import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/api_client.dart';
import '../services/call_launcher.dart';
import '../services/door_opener.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'nw_widgets.dart';

/// Main door action outside a call. With `door_open_remote` the PBX opens the
/// door via its webhook ("Tür öffnen", green "Tür geöffnet ✓" for 2 s plus a
/// double haptic pulse); otherwise opening needs the DTMF code inside a call,
/// so the button calls the door ("Tür anrufen").
///
/// [compact] is the small variant of the Kontakte row ("Öffnen"/"Anrufen").
class DoorOpenButton extends StatefulWidget {
  const DoorOpenButton({super.key, required this.door, this.compact = false, this.opener, this.onCall});

  final Contact door;
  final bool compact;

  /// Test seam (default: [DoorOpener.instance]).
  final DoorOpener? opener;

  /// Calls the door (default: [CallLauncher.call]).
  final VoidCallback? onCall;

  @override
  State<DoorOpenButton> createState() => _DoorOpenButtonState();
}

class _DoorOpenButtonState extends State<DoorOpenButton> {
  bool _running = false;
  bool _done = false;
  Timer? _doneTimer;

  DoorOpener get _opener => widget.opener ?? DoorOpener.instance;

  @override
  void dispose() {
    _doneTimer?.cancel();
    super.dispose();
  }

  void _call() {
    final onCall = widget.onCall;
    if (onCall != null) {
      onCall();
    } else {
      CallLauncher.call(context, widget.door.number);
    }
  }

  Future<void> _open() async {
    if (_running) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _running = true);
    try {
      final result = await _opener.open(widget.door.number);
      if (!mounted) return;
      if (result == DoorOpenResult.noWebhook) {
        messenger.showSnackBar(SnackBar(
          content: const Text('Für diese Tür ist kein Öffnen ohne Anruf eingerichtet.'),
          action: SnackBarAction(label: 'Anrufen', onPressed: _call),
        ));
        return;
      }
      doorOpenedHaptic();
      setState(() => _done = true);
      _doneTimer?.cancel();
      _doneTimer = Timer(kDoorOpenedFeedback, () {
        if (mounted) setState(() => _done = false);
      });
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Tür nicht geöffnet: ${e.message}')));
    } catch (e) {
      debugPrint('door open failed: $e');
      messenger.showSnackBar(const SnackBar(content: Text('Tür nicht geöffnet.')));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final door = widget.door;
    final remote = door.doorOpenRemote;
    final (Color bg, Color fg) = _done
        ? (c.okSurface, c.okText)
        : widget.compact
            ? (c.doorSoft, c.door)
            : (c.door, c.doorInk);
    final label = !remote
        ? (widget.compact ? 'Anrufen' : 'Tür anrufen')
        : _done
            ? (widget.compact ? 'Offen ✓' : 'Tür geöffnet ✓')
            : (widget.compact ? 'Öffnen' : 'Tür öffnen');
    final semantics = !remote
        ? '${door.displayName} anrufen'
        : _done
            ? '${door.displayName}: Tür geöffnet'
            : '${door.displayName}: Tür öffnen';
    final icon = _done ? Icons.check_rounded : Icons.door_front_door_outlined;
    final onPressed = remote ? _open : _call;
    final key = ValueKey('${remote ? 'door-open' : 'door-call'}-${door.number}');
    final Widget button;
    if (widget.compact) {
      button = FilledButton.icon(
        key: key,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          minimumSize: const Size(kMinTap, kMinTap),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: NwType.chip.copyWith(fontWeight: FontWeight.w800, fontSize: 12.5),
        ),
        onPressed: onPressed,
        icon: _running ? _spinner(fg, 14) : Icon(icon, size: 16),
        label: Text(label),
      );
    } else {
      button = FilledButton(
        key: key,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          minimumSize: const Size(kMinTap, 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: NwType.button,
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _running ? _spinner(fg, 18) : Icon(icon, size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      );
    }
    return Semantics(
      button: true,
      label: semantics,
      liveRegion: _done,
      onTap: onPressed,
      excludeSemantics: true,
      child: button,
    );
  }

  Widget _spinner(Color color, double size) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
      );
}
