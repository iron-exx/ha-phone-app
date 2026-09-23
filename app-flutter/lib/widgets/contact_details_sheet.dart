import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/favorites_store.dart';
import '../theme/app_colors.dart';
import 'contact_avatar.dart';

/// Long-press details: big avatar, number, status, Anrufen + Favorit.
class ContactDetailsSheet extends StatelessWidget {
  const ContactDetailsSheet({super.key, required this.contact, required this.onCall});

  final Contact contact;
  final VoidCallback onCall;

  static Future<void> show(BuildContext context, Contact contact, {required VoidCallback onCall}) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ContactDetailsSheet(contact: contact, onCall: onCall),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final favorites = FavoritesStore.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ContactAvatar(
              name: contact.name,
              number: contact.number,
              presence: contact.isExtension ? contact.presence : null,
              size: 72,
            ),
            const SizedBox(height: 12),
            Text(contact.displayName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              contact.isExtension
                  ? 'Nebenstelle ${contact.number} · ${contact.presence.label}'
                  : contact.number,
              style: tabular(theme.textTheme.bodyMedium)?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (contact.isDoorStation) ...[
              const SizedBox(height: 4),
              Text('Türstation', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.answer,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: const Icon(Icons.call),
                    label: const Text('Anrufen'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      onCall();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ListenableBuilder(
                    listenable: favorites,
                    builder: (context, _) {
                      final fav = favorites.isFavorite(contact.number);
                      return OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        icon: Icon(fav ? Icons.star : Icons.star_border),
                        label: Text(fav ? 'Favorit entfernen' : 'Favorit'),
                        onPressed: () => favorites.toggle(contact.number),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
