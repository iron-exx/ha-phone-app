import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Round in-call action (Stumm, Halten, ...) with a label underneath.
/// [active] fills the circle with the accent colour; a null [onPressed]
/// renders it disabled.
class RoundActionButton extends StatelessWidget {
  const RoundActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.size = 68,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final enabled = onPressed != null;
    // Nachtwache control key: raised tile, radius 22; active = inverted.
    final bg = active ? c.text : c.raised;
    final fg = active ? c.ground : c.text;
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: active,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        // The whole button incl. label is the touch target (>= 64 dp wide).
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
                  child: Icon(icon, color: fg, size: 26),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Large coloured round call button (green = call/answer, red = hang up).
class CallButton extends StatelessWidget {
  const CallButton({
    super.key,
    required this.color,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 76,
    this.foreground = Colors.white,
  });

  final Color color;
  final Color foreground;
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onPressed == null ? color.withOpacity(0.4) : color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: foreground, size: size * 0.42),
          ),
        ),
      ),
    );
  }
}
