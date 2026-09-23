import 'package:flutter/material.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final bg = active ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = active ? scheme.onPrimary : scheme.onSurface;
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
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Icon(icon, color: fg, size: 28),
                ),
                const SizedBox(height: 8),
                Text(label, style: Theme.of(context).textTheme.labelMedium, textAlign: TextAlign.center),
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
    this.size = 72,
  });

  final Color color;
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
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
        ),
      ),
    );
  }
}
