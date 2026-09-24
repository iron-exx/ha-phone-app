import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../models/extension_status.dart';
import '../services/call_launcher.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'nw_widgets.dart';
import 'presence_avatar.dart';

/// Round "Anrufen" button of a list row: `raised`, green phone, 48 dp.
class RowCallButton extends StatelessWidget {
  const RowCallButton({super.key, required this.label, required this.onPressed});

  /// TalkBack label, e.g. "sandro anrufen".
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return NwIconButton(
      icon: Icons.call,
      label: label,
      onPressed: onPressed,
      radius: 14,
      color: c.raised,
      iconColor: c.answer,
      iconSize: 19,
    );
  }
}

/// Contacts-list row: avatar with presence ring, name (+ star), coloured
/// status word and number ("telefoniert · 11"), call button on the right.
/// A ringing colleague offers "Heranholen" instead (PBX code **<ext>).
/// [status] is the live presence/line state; without it the directory's
/// presence is shown.
class ContactTile extends StatelessWidget {
  const ContactTile({
    super.key,
    required this.contact,
    required this.isFavorite,
    required this.onTap,
    required this.onLongPress,
    required this.onCall,
    this.status,
  });

  final Contact contact;
  final bool isFavorite;

  /// Row tap: details sheet.
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onCall;
  final ExtensionStatus? status;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final live = status ?? ExtensionStatus(presence: contact.presence);
    final kind = contact.isExtension ? avatarPresenceFor(live) : null;
    final statusColor = kind == null || kind == AvatarPresence.offline ? c.faint : kind.color(c);
    final subtitle = contact.isExtension
        ? Text.rich(
            TextSpan(children: [
              TextSpan(text: live.label, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700)),
              TextSpan(text: ' · ${contact.number}', style: TextStyle(color: c.faint)),
            ]),
            style: NwType.meta,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          )
        : Text(
            contact.label.isNotEmpty ? '${contact.label} · ${contact.number}' : contact.number,
            style: NwType.meta.copyWith(color: c.faint),
            overflow: TextOverflow.ellipsis,
          );
    final ringing = live.line == LineState.ringing && contact.isExtension;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              PresenceAvatar(name: contact.name, number: contact.number, presence: kind, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            contact.displayName,
                            style: NwType.rowTitle.copyWith(color: c.text),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isFavorite) ...[
                          const SizedBox(width: 6),
                          Semantics(label: 'Favorit', child: Icon(Icons.star_rounded, size: 16, color: c.blue)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    subtitle,
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (ringing)
                FilledButton.tonalIcon(
                  key: Key('pickup-${contact.number}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.okSurface,
                    foregroundColor: c.okText,
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () => CallLauncher.call(context, '**${contact.number}'),
                  icon: const Icon(Icons.call_received, size: 18),
                  label: const Text('Heranholen'),
                )
              else
                RowCallButton(label: '${contact.displayName} anrufen', onPressed: onCall),
            ],
          ),
        ),
      ),
    );
  }
}
