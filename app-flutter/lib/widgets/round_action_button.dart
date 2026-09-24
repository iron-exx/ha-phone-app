import 'package:flutter/material.dart';

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
