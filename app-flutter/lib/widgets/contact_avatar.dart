import 'package:flutter/material.dart';

import '../models/presence.dart';
import '../utils/contact_filter.dart';

/// Initials avatar with an optional presence dot (bottom right), as in Linkus.
class ContactAvatar extends StatelessWidget {
  const ContactAvatar({
    super.key,
    required this.name,
    required this.number,
    this.presence,
    this.dotColor,
    this.size = 44,
    this.color,
  });

  final String name;
  final String number;

  /// null = no dot (phonebook entries, unknown callers).
  final Presence? presence;

  /// Overrides the presence colour of the dot (live line state, e.g. red
  /// while the extension is on the phone). Shows a dot even without [presence].
  final Color? dotColor;
  final double size;

  /// Overrides the tinted accent background (e.g. red for missed calls).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.primary;
    final dot = size * 0.3;
    final dotFill = dotColor ?? presence?.color;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: fg.withOpacity(0.15)),
            child: Text(
              initialsFor(name, number),
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: size * 0.36,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (dotFill != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotFill,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
