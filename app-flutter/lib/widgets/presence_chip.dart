import 'package:flutter/material.dart';

import '../models/presence.dart';

/// Coloured status pill, e.g. in the Ich tab. With [onTap] it shows a
/// dropdown arrow and opens the status picker.
class PresenceChip extends StatelessWidget {
  const PresenceChip({super.key, required this.presence, this.onTap});
  final Presence presence;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Material(
      color: presence.color.withOpacity(0.15),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 6, onTap == null ? 12 : 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(shape: BoxShape.circle, color: presence.color),
              ),
              const SizedBox(width: 8),
              Text(presence.label, style: Theme.of(context).textTheme.labelLarge),
              if (onTap != null) const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
