import 'package:flutter/material.dart';

import '../models/voicemail.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'contact_avatar.dart';

/// Voicemail-list row: avatar, name or number (bold + blue dot while
/// unheard), "0:42 · heute 14:02".
class VoicemailTile extends StatelessWidget {
  const VoicemailTile({
    super.key,
    required this.message,
    required this.resolvedName,
    required this.isUnheard,
    required this.isExpanded,
    required this.now,
    required this.onTap,
  });

  final VoicemailMessage message;

  /// caller_name, or the directory name for the number, or ''.
  final String resolvedName;
  final bool isUnheard;
  final bool isExpanded;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = message.callerNumber;
    final title = resolvedName.isNotEmpty ? resolvedName : (number.isNotEmpty ? number : 'Unbekannt');
    final weight = isUnheard ? FontWeight.w700 : FontWeight.w400;
    return ListTile(
      onTap: onTap,
      selected: isExpanded,
      selectedTileColor: theme.colorScheme.primary.withOpacity(0.06),
      leading: ContactAvatar(name: resolvedName, number: number),
      title: Text(
        title,
        overflow: TextOverflow.ellipsis,
        style: tabular(theme.textTheme.bodyLarge)?.copyWith(fontWeight: weight, color: theme.colorScheme.onSurface),
      ),
      subtitle: Text(
        voicemailSubtitle(message.duration, message.receivedAt, now),
        style: tabular(theme.textTheme.bodyMedium)?.copyWith(
          fontWeight: isUnheard ? FontWeight.w600 : null,
        ),
      ),
      trailing: isUnheard
          ? Semantics(
              label: 'neu',
              child: Container(
                key: const ValueKey('voicemail-new-dot'),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.brightness == Brightness.dark ? AppColors.haBlueLight : AppColors.haBlue,
                ),
              ),
            )
          : null,
    );
  }
}
