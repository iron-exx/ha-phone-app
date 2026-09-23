/// Forwarding rules per presence status (GET/PUT /api/mobile/forwarding,
/// HA-Phone 0.7.110+). A missing rule for a status + direction means
/// "Normal klingeln".
enum ForwardDirection {
  internal('internal', 'Interne Anrufe'),
  external('external', 'Externe Anrufe');

  const ForwardDirection(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ForwardDirection? fromApi(String? v) {
    for (final d in values) {
      if (d.apiValue == v) return d;
    }
    return null;
  }
}

enum ForwardMode {
  /// "Erst klingeln, dann …" after [ForwardingRule.ringTimeout] seconds.
  ringThenDest('ring_then_dest'),

  /// "Sofort …".
  alwaysDest('always_dest');

  const ForwardMode(this.apiValue);
  final String apiValue;

  static ForwardMode fromApi(String? v) => v == 'ring_then_dest' ? ringThenDest : alwaysDest;
}

enum ForwardDestType {
  extension('extension'),

  /// Ring groups are not in the directory: shown read-only, sent back unchanged.
  ringGroup('ring_group'),
  voicemail('voicemail'),
  hangup('hangup');

  const ForwardDestType(this.apiValue);
  final String apiValue;

  static ForwardDestType fromApi(String? v) {
    for (final t in values) {
      if (t.apiValue == v) return t;
    }
    return hangup;
  }
}

const kMinRingTimeout = 5;
const kMaxRingTimeout = 60;
const kDefaultRingTimeout = 20;

class ForwardingRule {
  const ForwardingRule({
    required this.status,
    required this.direction,
    required this.mode,
    required this.destType,
    this.destTarget = '',
    this.ringTimeout = kDefaultRingTimeout,
    this.raw,
  });

  factory ForwardingRule.fromJson(Map<String, dynamic> json) => ForwardingRule(
        status: (json['status'] ?? '').toString(),
        direction: ForwardDirection.fromApi(json['direction'] as String?) ?? ForwardDirection.internal,
        mode: ForwardMode.fromApi(json['mode'] as String?),
        destType: ForwardDestType.fromApi(json['dest_type'] as String?),
        destTarget: (json['dest_target'] ?? '').toString(),
        ringTimeout: (json['ring_timeout'] as num?)?.toInt() ?? kDefaultRingTimeout,
        raw: json,
      );

  /// Presence api value: available, away, lunch, do_not_disturb, off_work.
  final String status;
  final ForwardDirection direction;
  final ForwardMode mode;
  final ForwardDestType destType;

  /// Extension number (extension/voicemail) or ring-group id (ring_group).
  final String destTarget;

  /// Seconds before forwarding in [ForwardMode.ringThenDest].
  final int ringTimeout;

  /// JSON as received; ring-group rules are sent back exactly like this.
  final Map<String, dynamic>? raw;

  bool get isRingGroup => destType == ForwardDestType.ringGroup;

  Map<String, dynamic> toJson() {
    final original = raw;
    if (isRingGroup && original != null) return original;
    return {
      ...?original,
      'status': status,
      'direction': direction.apiValue,
      'mode': mode.apiValue,
      'dest_type': destType.apiValue,
      // The PBX expects an int (0 for hangup).
      'dest_target': destType == ForwardDestType.hangup ? 0 : (int.tryParse(destTarget) ?? destTarget),
      'ring_timeout': ringTimeout,
    };
  }

  bool matches(String status, ForwardDirection direction) =>
      this.status == status && this.direction == direction;
}

/// Parses the {"rules":[...]} body.
List<ForwardingRule> parseForwardingRules(Map<String, dynamic> json) {
  final raw = json['rules'];
  if (raw is! List) return const [];
  return raw.whereType<Map<String, dynamic>>().map(ForwardingRule.fromJson).toList();
}

Map<String, dynamic> forwardingRulesToJson(List<ForwardingRule> rules) =>
    {'rules': rules.map((r) => r.toJson()).toList()};

ForwardingRule? ruleFor(List<ForwardingRule> rules, String status, ForwardDirection direction) {
  for (final r in rules) {
    if (r.matches(status, direction)) return r;
  }
  return null;
}

/// New full list with the rule for [status] + [direction] replaced by
/// [rule] (null = "Normal klingeln", i.e. removed). All other rules,
/// including ring-group rules, stay untouched and in order.
List<ForwardingRule> replaceRule(
  List<ForwardingRule> rules,
  String status,
  ForwardDirection direction,
  ForwardingRule? rule,
) {
  final result = <ForwardingRule>[];
  var replaced = false;
  for (final r in rules) {
    if (!r.matches(status, direction)) {
      result.add(r);
    } else if (!replaced && rule != null) {
      result.add(rule);
      replaced = true;
    } else {
      replaced = true;
    }
  }
  if (!replaced && rule != null) result.add(rule);
  return result;
}

/// Plain German behaviour: "Normal klingeln", "Sofort zur Mailbox",
/// "Nach 20 s zu 11 · sandro", "Ablehnen". [nameFor] resolves extension names.
String describeRule(ForwardingRule? rule, String Function(String number) nameFor) {
  if (rule == null) return 'Normal klingeln';
  final dest = switch (rule.destType) {
    ForwardDestType.voicemail => 'zur Mailbox',
    ForwardDestType.ringGroup => 'zur Klingelgruppe',
    ForwardDestType.hangup => 'ablehnen',
    ForwardDestType.extension => _toExtension(rule.destTarget, nameFor),
  };
  if (rule.mode == ForwardMode.ringThenDest) return 'Nach ${rule.ringTimeout} s $dest';
  if (rule.destType == ForwardDestType.hangup) return 'Ablehnen';
  return 'Sofort $dest';
}

String _toExtension(String number, String Function(String number) nameFor) {
  final name = nameFor(number);
  return name.isEmpty ? 'zu $number' : 'zu $number · $name';
}
