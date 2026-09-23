import 'package:flutter/material.dart';

import '../models/extension_status.dart';
import '../models/presence.dart';
import '../services/api_client.dart';
import '../services/directory_repository.dart';
import '../services/presence_repository.dart';
import '../theme/app_colors.dart';
import 'contact_avatar.dart';
import 'presence_chip.dart';
import 'presence_sheet.dart';

/// Top of the Ich tab: own avatar, name, extension, tappable presence chip
/// and the live line state ("frei", "telefoniert", ...).
class OwnStatusHeader extends StatelessWidget {
  const OwnStatusHeader({super.key, DirectoryRepository? directory, PresenceRepository? presence})
      : _directory = directory,
        _presence = presence;

  final DirectoryRepository? _directory;
  final PresenceRepository? _presence;

  DirectoryRepository get _dir => _directory ?? DirectoryRepository.instance;
  PresenceRepository get _pres => _presence ?? PresenceRepository.instance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_dir, _pres]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final self = _dir.directory?.self;
    final live = _pres.snapshot?.self;
    final presence = live?.presence ?? self?.presence ?? Presence.unknown;
    final status = ExtensionStatus(presence: presence, line: live?.line ?? LineState.unknown);
    final hint = _hint();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ContactAvatar(
            name: self?.name ?? '',
            number: self?.number ?? _pres.snapshot?.selfNumber ?? '',
            presence: presence,
            dotColor: status.color,
            size: 64,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(self?.displayName ?? 'Eigene Nebenstelle', style: theme.textTheme.titleLarge),
                Text(
                  self == null ? 'Noch nicht geladen' : 'Nebenstelle ${self.number}',
                  style: tabular(theme.textTheme.bodyMedium),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PresenceChip(presence: presence, onTap: () => _pick(context, presence)),
                    if (status.line != LineState.unknown) _lineLabel(theme, status.line),
                  ],
                ),
                if (hint != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _hint() {
    final error = _pres.error;
    if (error == null || _pres.snapshot != null) return null;
    return error.kind == ApiErrorKind.unsupported ? error.message : null;
  }

  Widget _lineLabel(ThemeData theme, LineState line) {
    final color = switch (line) {
      LineState.busy || LineState.ringing => AppColors.presenceBusy,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.phone_in_talk_outlined, size: 16, color: color),
        const SizedBox(width: 4),
        Text('Leitung: ${line.label}', style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }

  Future<void> _pick(BuildContext context, Presence current) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await PresenceSheet.show(context, current);
    if (picked == null || picked == current) return;
    try {
      await _pres.setOwn(picked);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Status nicht gespeichert: ${e.message}')));
    }
  }
}
