import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../theme/app_colors.dart';
import 'contact_avatar.dart';

/// Contacts-list row: avatar with presence dot, name, "13 · verfügbar".
class ContactTile extends StatelessWidget {
  const ContactTile({
    super.key,
    required this.contact,
    required this.isFavorite,
    required this.onTap,
    required this.onLongPress,
  });

  final Contact contact;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = contact.isExtension ? '${contact.number} · ${contact.presence.label}' : contact.number;
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: ContactAvatar(
        name: contact.name,
        number: contact.number,
        presence: contact.isExtension ? contact.presence : null,
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
      trailing: contact.isDoorStation
          ? Tooltip(
              message: 'Türstation',
              child: Icon(Icons.door_front_door_outlined, color: theme.colorScheme.primary),
            )
          : null,
    );
  }
}
