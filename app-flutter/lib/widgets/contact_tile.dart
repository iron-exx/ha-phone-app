import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../models/extension_status.dart';
import '../services/call_launcher.dart';
import '../theme/app_colors.dart';
import 'contact_avatar.dart';

/// Contacts-list row: avatar with status dot, name, "13 · verfügbar" or
/// "11 · telefoniert". [status] is the live presence/line state; without it
/// the directory's presence is shown.
class ContactTile extends StatelessWidget {
  const ContactTile({
    super.key,
    required this.contact,
    required this.isFavorite,
    required this.onTap,
    required this.onLongPress,
    this.status,
  });

  final Contact contact;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ExtensionStatus? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = status ?? ExtensionStatus(presence: contact.presence);
    final subtitle = contact.isExtension
        ? '${contact.number} · ${live.label}'
        : contact.label.isNotEmpty
            ? '${contact.label} · ${contact.number}'
            : contact.number;
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: ContactAvatar(
        name: contact.name,
        number: contact.number,
        presence: contact.isExtension ? live.presence : null,
        dotColor: contact.isExtension ? live.color : null,
      ),
      title: Row(
        children: [
          Flexible(child: Text(contact.displayName, overflow: TextOverflow.ellipsis)),
          if (isFavorite) ...[
            const SizedBox(width: 6),
            Icon(Icons.star, size: 16, color: theme.colorScheme.primary),
          ],
        ],
      ),
      subtitle: Text(subtitle, style: tabular(theme.textTheme.bodyMedium)),
      // A ringing colleague: take the call over (PBX code **<ext>), like the desk phone's BLF key.
      trailing: live.line == LineState.ringing && contact.isExtension
          ? FilledButton.tonalIcon(
              key: Key('pickup-${contact.number}'),
              onPressed: () => CallLauncher.call(context, '**${contact.number}'),
              icon: const Icon(Icons.call_received, size: 18),
              label: const Text('Heranholen'),
            )
          : contact.isDoorStation
          ? Tooltip(
              message: 'Türstation',
              child: Icon(Icons.door_front_door_outlined, color: theme.colorScheme.primary),
            )
          : null,
    );
  }
}
