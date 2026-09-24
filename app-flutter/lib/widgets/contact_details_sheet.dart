import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../models/extension_status.dart';
import '../services/favorites_store.dart';
import '../services/presence_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'door_open_button.dart';
import 'presence_avatar.dart';

/// Long-press details: big avatar, number, live status (like the list rows:
/// "telefoniert" wins over the presence), Anrufen + Favorit.
class ContactDetailsSheet extends StatelessWidget {
  const ContactDetailsSheet({super.key, required this.contact, required this.onCall, PresenceRepository? presence})
      : _presence = presence;

  final Contact contact;
  final VoidCallback onCall;
  final PresenceRepository? _presence;

  static Future<void> show(
    BuildContext context,
    Contact contact, {
    required VoidCallback onCall,
    PresenceRepository? presence,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ContactDetailsSheet(contact: contact, onCall: onCall, presence: presence),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presence = _presence ?? PresenceRepository.instance;
    return ListenableBuilder(
      listenable: presence,
      builder: (context, _) => _build(
        context,
        (contact.isExtension ? presence.statusFor(contact.number) : null) ??
            ExtensionStatus(presence: contact.presence),
      ),
    );
  }

  Widget _build(BuildContext context, ExtensionStatus live) {
    final theme = Theme.of(context);
    final c = context.nw;
    final favorites = FavoritesStore.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (contact.isDoorStation)
              const PresenceAvatar.door(size: 72)
            else
              PresenceAvatar(
                name: contact.name,
                number: contact.number,
                presence: contact.isExtension ? avatarPresenceFor(live) : null,
                size: 72,
              ),
            const SizedBox(height: 12),
            Text(contact.displayName, style: NwType.display(26).copyWith(color: c.text), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              contact.isExtension
                  ? 'Nebenstelle ${contact.number} · ${live.label}'
                  : contact.number,
              style: tabular(theme.textTheme.bodyMedium)?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (contact.isDoorStation) ...[
              const SizedBox(height: 4),
              Text('Türstation', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 24),
            if (contact.doorOpenRemote) ...[
              SizedBox(width: double.infinity, child: DoorOpenButton(door: contact)),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.answer,
                      foregroundColor: c.answerInk,
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
