import 'package:flutter/material.dart';

import '../models/presence.dart';

/// Coloured status pill, e.g. in the Ich tab.
class PresenceChip extends StatelessWidget {
  const PresenceChip({super.key, required this.presence});
  final Presence presence;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: presence.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
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
        ],
      ),
    );
  }
}
