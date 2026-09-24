import '../models/forwarding.dart';
import '../models/presence.dart';

/// Statuses of "Status für alle", in mockup order (Mittagspause only shows
/// while it is the current status, e.g. set on the desk phone).
List<Presence> statusChoices(Presence current) => [
      Presence.available,
      Presence.away,
      if (current == Presence.lunch) Presence.lunch,
      Presence.doNotDisturb,
      Presence.offWork,
    ];

/// Generic sub-line while the forwarding rules are unknown (older PBX, offline).
String genericPresenceHint(Presence p) => switch (p) {
      Presence.available => 'Anrufe klingeln wie eingestellt',
      Presence.away => 'Weiterleitung nach Regel „abwesend“',
      Presence.lunch => 'Weiterleitung nach Regel „Mittagspause“',
      Presence.doNotDisturb => 'Keine Anrufe, Regel „nicht stören“',
      Presence.offWork => 'Weiterleitung nach Regel „Feierabend“',
      Presence.unknown => '',
    };

/// What happens to calls in status [p], from the forwarding rules:
/// "Nach 20 s zur Mailbox", or "Intern: Normal klingeln · Extern: Sofort zur
/// Mailbox" when the directions differ. [rules] null = not loaded.
String presenceHint(Presence p, List<ForwardingRule>? rules, String Function(String number) nameFor) {
  if (rules == null || p == Presence.unknown) return genericPresenceHint(p);
  final internal = describeRule(ruleFor(rules, p.apiValue, ForwardDirection.internal), nameFor);
  final external = describeRule(ruleFor(rules, p.apiValue, ForwardDirection.external), nameFor);
  if (internal == external) return internal;
  return 'Intern: $internal · Extern: $external';
}
