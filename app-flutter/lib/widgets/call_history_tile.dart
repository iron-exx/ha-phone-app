import 'package:flutter/material.dart';

import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'contact_avatar.dart';

/// Anrufe-list row. [resolvedName] comes from the directory when the native
/// entry has no name.
class CallHistoryTile extends StatelessWidget {
  const CallHistoryTile({
    super.key,
    required this.entry,
    required this.resolvedName,
    required this.now,
    required this.onTap,
  });

  final CallHistoryEntry entry;
  final String resolvedName;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missedColor = entry.missed ? AppColors.hangup : null;
    final title = resolvedName.isNotEmpty ? resolvedName : entry.number;
    return ListTile(
      onTap: onTap,
      leading: ContactAvatar(name: resolvedName, number: entry.number, color: missedColor),
      title: Text(
        title,
        overflow: TextOverflow.ellipsis,
        style: tabular(theme.textTheme.bodyLarge)?.copyWith(color: missedColor),
      ),
      subtitle: Row(
        children: [
          Icon(_directionIcon(), size: 14, color: missedColor ?? theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              callSubtitle(entry),
              overflow: TextOverflow.ellipsis,
              style: tabular(theme.textTheme.bodyMedium)?.copyWith(color: missedColor),
            ),
          ),
        ],
      ),
      trailing: Text(
        formatHistoryTime(entry.startedAt, now),
        style: tabular(theme.textTheme.bodySmall)?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  IconData _directionIcon() {
    if (entry.missed) return Icons.call_missed;
    if (entry.video) return Icons.videocam_outlined;
    return entry.direction == 'incoming' ? Icons.call_received : Icons.call_made;
  }
}
