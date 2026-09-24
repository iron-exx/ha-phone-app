import 'package:flutter/material.dart';

import '../models/extension_status.dart';
import '../models/presence.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/contact_filter.dart';

/// What the avatar shows: colour **and** shape, so it also works for
/// colour-blind users (ring + glyph bottom right). [offline] has no ring.
enum AvatarPresence {
  available('verfügbar', Icons.check_rounded),
  away('abwesend', Icons.nightlight_round),
  doNotDisturb('nicht stören', Icons.remove_rounded),
  busy('telefoniert', Icons.call),
  offWork('Feierabend', Icons.bedtime_outlined),
  offline('offline', null);

  const AvatarPresence(this.label, this.glyph);

  /// German status word (also the TalkBack label of the avatar).
  final String label;

  /// Glyph in the small badge, null = no badge.
  final IconData? glyph;

  Color color(NwColors c) => switch (this) {
        available => c.answer,
        away => c.door,
        doNotDisturb || busy => c.end,
        offWork => c.faint,
        offline => c.offline,
      };
}

/// Maps the live status of an extension to the avatar. The line state wins
/// (someone on the phone is "telefoniert" whatever they set; ringing counts
/// as busy). Returns null when nothing is known (plain avatar, no ring).
AvatarPresence? avatarPresenceFor(ExtensionStatus? status) {
  if (status == null) return null;
  switch (status.line) {
    case LineState.busy || LineState.ringing:
      return AvatarPresence.busy;
    case LineState.offline:
      return AvatarPresence.offline;
    case LineState.idle || LineState.unknown:
      break;
  }
  return switch (status.presence) {
    Presence.available => AvatarPresence.available,
    Presence.away || Presence.lunch => AvatarPresence.away,
    Presence.doNotDisturb => AvatarPresence.doNotDisturb,
    Presence.offWork => AvatarPresence.offWork,
    // Registered and idle but no presence set: reachable.
    Presence.unknown => status.line == LineState.idle ? AvatarPresence.available : null,
  };
}

/// Initials avatar of the Nachtwache design: `high` circle, optional
/// presence ring + glyph. [icon] replaces the initials (door stations use a
/// rounded square with the amber door symbol, see [PresenceAvatar.door]).
class PresenceAvatar extends StatelessWidget {
  const PresenceAvatar({
    super.key,
    required this.name,
    required this.number,
    this.presence,
    this.size = 44,
    this.background,
    this.foreground,
  })  : icon = null,
        _door = false;

  /// Door station: rounded amber-soft square with the door symbol.
  const PresenceAvatar.door({super.key, this.size = 46})
      : name = '',
        number = '',
        presence = null,
        background = null,
        foreground = null,
        icon = Icons.door_front_door_outlined,
        _door = true;

  final String name;
  final String number;

  /// null = no ring and no glyph (phonebook, unknown callers).
  final AvatarPresence? presence;
  final double size;
  final Color? background;
  final Color? foreground;
  final IconData? icon;
  final bool _door;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    if (_door) {
      return ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: c.doorSoft, borderRadius: BorderRadius.circular(size / 3)),
          child: Icon(icon, color: c.door, size: size * 0.48),
        ),
      );
    }
    final p = presence;
    final ringColor = p?.color(c);
    final glyph = p?.glyph;
    final badge = (size * 0.38).clamp(16.0, 30.0);
    return Semantics(
      label: p?.label,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: background ?? c.high),
              child: ExcludeSemantics(
                child: MediaQuery.withNoTextScaling(
                  child: Text(
                    initialsFor(name, number),
                    style: TextStyle(
                      fontFamily: NwFonts.ui,
                      color: foreground ?? c.text,
                      fontWeight: FontWeight.w800,
                      fontSize: size * 0.36,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            if (ringColor != null && p != AvatarPresence.offline)
              Positioned(
                left: -3,
                top: -3,
                right: -3,
                bottom: -3,
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: const ValueKey('presence-ring'),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ringColor, width: 2.5),
                    ),
                  ),
                ),
              ),
            if (ringColor != null && glyph != null)
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  key: const ValueKey('presence-glyph'),
                  width: badge,
                  height: badge,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ringColor,
                    border: Border.all(color: c.ground, width: 2.5),
                  ),
                  child: Icon(glyph, size: badge * 0.55, color: c.ground),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
