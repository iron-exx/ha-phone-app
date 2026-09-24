import 'package:flutter/material.dart';

import '../services/directory_repository.dart';
import '../services/sip_channel.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'nw_widgets.dart';
import 'presence_avatar.dart';

/// Compact card at the top of the call screen for the second line: the held
/// call ("gehalten · 01:02" + "Tauschen"), a knocking call (Ablehnen /
/// Annehmen) or the conference partner. "Zusammenführen" and "Verbinden"
/// sit under the main caller (see ActiveCallScreen).
class SecondCallCard extends StatelessWidget {
  const SecondCallCard({
    super.key,
    required this.other,
    required this.conference,
    required this.onAnswerWaiting,
    required this.onRejectWaiting,
    required this.onSwap,
    this.directory,
    this.presence,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CurrentCall other;
  final bool conference;
  final VoidCallback onAnswerWaiting;
  final VoidCallback onRejectWaiting;
  final VoidCallback onSwap;
  final DirectoryRepository? directory;

  /// Presence of the other party (ring on the small avatar), null = none.
  final AvatarPresence? presence;
  final DateTime Function() _clock;

  String get _name {
    if (other.name.isNotEmpty) return other.name;
    final fromDirectory = (directory ?? DirectoryRepository.instance).nameFor(other.number);
    return fromDirectory.isNotEmpty ? fromDirectory : other.number;
  }

  String get _status {
    if (other.isWaiting) return 'klopft an';
    final since = other.connectedAt;
    final timer = since == null ? '' : ' · ${formatCallTimer(_clock().difference(since))}';
    if (conference) return 'in Konferenz$timer';
    return 'gehalten$timer';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final waiting = other.isWaiting;
    final name = _name;
    final statusColor = waiting ? c.blue : (conference ? c.okText : c.door);
    // Large system text: actions move under the name instead of squeezing it.
    final stacked = MediaQuery.textScalerOf(context).scale(10) / 10 >= 1.5;
    final avatar = PresenceAvatar(name: other.name, number: other.number, presence: presence, size: 38);
    final info = Semantics(
      container: true,
      label: waiting
          ? 'Anklopfen: $name'
          : conference
              ? 'Konferenz mit $name'
              : 'Gehalten: $name',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              waiting ? 'Anklopfen: $name' : name,
              style: NwType.rowTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w800, color: c.text),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(_status, style: NwType.meta.copyWith(fontSize: 12, color: statusColor)),
          ],
        ),
      ),
    );
    final actions = <Widget>[
      if (waiting) ...[
        NwIconButton(
          key: const Key('reject-waiting'),
          icon: Icons.call_end,
          label: 'Ablehnen',
          color: c.end,
          iconColor: c.endInk,
          radius: 24,
          onPressed: onRejectWaiting,
        ),
        NwIconButton(
          key: const Key('answer-waiting'),
          icon: Icons.call,
          label: 'Annehmen',
          color: c.answer,
          iconColor: c.answerInk,
          radius: 24,
          onPressed: onAnswerWaiting,
        ),
      ] else if (!conference)
        NwChip(
          key: const Key('swap'),
          label: 'Tauschen',
          icon: Icons.swap_horiz,
          semanticLabel: 'Leitungen tauschen, $name nach vorn holen',
          onTap: onSwap,
        ),
    ];
    return Container(
      key: const Key('second-call'),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: waiting ? c.blueSoft : c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: waiting ? c.blue : c.stroke),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [avatar, const SizedBox(width: 12), Expanded(child: info)]),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 4, children: actions),
                ],
              ],
            )
          : Row(
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(child: info),
                for (final a in actions) ...[const SizedBox(width: 8), a],
              ],
            ),
    );
  }
}
