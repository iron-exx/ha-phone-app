import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/timeline.dart';
import 'presence_avatar.dart';

/// One Verlauf row: avatar (door symbol for door stations), name (bold with
/// a coloured bar on the left while unread), a coloured meta line with an
/// icon, the time, and optional [extra] content (inline player).
class TimelineRow extends StatelessWidget {
  const TimelineRow({
    super.key,
    required this.item,
    required this.name,
    required this.isDoor,
    required this.isUnread,
    this.presence,
    this.extra,
    this.onTap,
  });

  final TimelineItem item;

  /// Resolved display name ('' = show the number).
  final String name;
  final bool isDoor;
  final bool isUnread;
  final AvatarPresence? presence;
  final Widget? extra;
  final VoidCallback? onTap;

  String get title {
    if (name.isNotEmpty) return name;
    return item.number.isNotEmpty ? item.number : 'Unbekannt';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final (icon, meta, accent) = _meta(c);
    final metaColor = item.isMissedCall || isDoor ? accent : c.muted;
    return InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          if (isUnread)
            Positioned(
              left: 0,
              top: 14,
              bottom: 14,
              child: Container(
                key: const ValueKey('unread-bar'),
                width: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                ),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  isDoor
                      ? const PresenceAvatar.door(size: 44)
                      : PresenceAvatar(name: name, number: item.number, presence: presence, size: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: NwType.rowTitle.copyWith(
                            color: c.text,
                            fontWeight: isUnread ? FontWeight.w800 : FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(icon, size: 14, color: accent),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                meta,
                                style: NwType.meta.copyWith(color: metaColor),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                        if (extra != null) extra!,
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      _clock(item.at),
                      style: NwType.meta.copyWith(color: c.faint, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  (IconData, String, Color) _meta(NwColors c) {
    switch (item.kind) {
      case TimelineKind.call:
        final call = item.call!;
        final entry = call.entry;
        final text = call.isOtherDevice ? '${callSubtitle(entry)} · anderes Gerät' : callSubtitle(entry);
        if (isDoor) return (Icons.door_front_door_outlined, text, c.door);
        if (entry.missed) return (Icons.call_missed, text, c.end);
        if (entry.video) return (Icons.videocam_outlined, text, c.muted);
        return (entry.direction == 'incoming' ? Icons.call_received : Icons.call_made, text, c.muted);
      case TimelineKind.voicemail:
        return (Icons.voicemail, 'Sprachnachricht · ${formatCallDuration(item.voicemail!.duration)}', c.blue);
      case TimelineKind.recording:
        return (Icons.fiber_manual_record, 'Aufnahme · ${formatCallDuration(item.recording!.duration)}', c.end);
    }
  }
}
