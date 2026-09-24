import 'package:flutter/material.dart';

import '../models/extension_status.dart';
import '../models/presence.dart';
import '../services/api_client.dart';
import '../services/directory_repository.dart';
import '../services/presence_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'presence_avatar.dart';
import 'presence_chip.dart';
import 'presence_sheet.dart';

/// Top of the Ich tab: own avatar with presence ring, name, extension,
/// tappable presence chip and the live line state ("frei", "telefoniert").
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
    final c = context.nw;
    final self = _dir.directory?.self;
    final live = _pres.snapshot?.self;
    final presence = live?.presence ?? self?.presence ?? Presence.unknown;
    final status = ExtensionStatus(presence: presence, line: live?.line ?? LineState.unknown);
    final hint = _hint();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: PresenceAvatar(
              name: self?.name ?? '',
              number: self?.number ?? _pres.snapshot?.selfNumber ?? '',
              presence: avatarPresenceFor(status),
              size: 60,
              background: c.blueSoft,
              foreground: c.blueOnSoft,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(self?.displayName ?? 'Eigene Nebenstelle', style: NwType.display(24).copyWith(color: c.text)),
                const SizedBox(height: 2),
                Text(
                  self == null ? 'Noch nicht geladen' : 'Nebenstelle ${self.number}',
                  style: NwType.meta.copyWith(color: c.faint, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PresenceChip(presence: presence, onTap: () => pickOwnPresence(context, _pres, presence)),
                    if (status.line != LineState.unknown) _lineLabel(c, status.line),
                  ],
                ),
                if (hint != null) ...[
                  const SizedBox(height: 4),
                  Text(hint, style: NwType.meta.copyWith(color: c.faint)),
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

  Widget _lineLabel(NwColors c, LineState line) {
    final color = switch (line) {
      LineState.busy || LineState.ringing => c.end,
      _ => c.muted,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.phone_in_talk_outlined, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text('Leitung: ${line.label}', style: NwType.meta.copyWith(color: color))),
      ],
    );
  }
}
