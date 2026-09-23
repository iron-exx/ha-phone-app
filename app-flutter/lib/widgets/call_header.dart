import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'contact_avatar.dart';

/// Top of the active-call screen: avatar, name, number, status, TLS lock.
class CallHeader extends StatelessWidget {
  const CallHeader({
    super.key,
    required this.name,
    required this.number,
    required this.status,
    required this.secure,
    required this.isDoor,
    this.compact = false,
  });

  final String name;
  final String number;
  final String status;
  final bool secure;
  final bool isDoor;

  /// Smaller avatar when the video box needs the space.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact) ...[
          ContactAvatar(name: name, number: number, size: 96),
          const SizedBox(height: 16),
        ],
        Text(
          name.isNotEmpty ? name : number,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (name.isNotEmpty && number.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            isDoor ? '$number · Türstation' : number,
            style: tabular(theme.textTheme.bodyLarge)?.copyWith(color: muted),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              status,
              key: const Key('call-status'),
              style: tabular(theme.textTheme.titleMedium)?.copyWith(color: muted),
            ),
            if (secure) ...[
              const SizedBox(width: 12),
              Icon(Icons.lock, size: 16, color: muted),
              const SizedBox(width: 2),
              Text('TLS', style: theme.textTheme.labelMedium?.copyWith(color: muted)),
            ],
          ],
        ),
      ],
    );
  }
}
