import 'package:flutter/material.dart';

import '../models/presence.dart';

/// The five presence states the user can pick, in Linkus order.
const kSelectablePresences = [
  Presence.available,
  Presence.away,
  Presence.lunch,
  Presence.doNotDisturb,
  Presence.offWork,
];

/// Bottom sheet "Status wählen": coloured dot per status, check mark on the
/// current one. Returns the picked status, or null when dismissed.
class PresenceSheet extends StatelessWidget {
  const PresenceSheet({super.key, required this.current});

  final Presence current;

  static Future<Presence?> show(BuildContext context, Presence current) => showModalBottomSheet<Presence>(
        context: context,
        showDragHandle: true,
        // Sized to its content (the default caps at 9/16 of the screen).
        isScrollControlled: true,
        builder: (_) => PresenceSheet(current: current),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Status wählen', style: theme.textTheme.titleMedium),
            ),
            for (final p in kSelectablePresences)
              ListTile(
                key: ValueKey('presence-${p.apiValue}'),
                leading: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.color),
                ),
                title: Text(p.label),
                trailing: p == current ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
                selected: p == current,
                onTap: () => Navigator.of(context).pop(p),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
