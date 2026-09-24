// "Klingeln auf diesem Handy": a LOCAL setting of this device (not the PBX
// presence). Stored natively (ring/RingPolicy.kt) because the incoming-call path
// rejects calls with 480 before the Flutter engine is involved.

String _two(int n) => n.toString().padLeft(2, '0');

String _hhmm(DateTime t) => '${t.hour}:${_two(t.minute)}';

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Hour of "bis morgen" / "bis 8:00 morgen".
const kMorningHour = 8;

/// Hour of the "bis 17:00" chip (end of the working day).
const kEveningHour = 17;

class RingSettings {
  const RingSettings({this.enabled = true, this.mutedUntil, this.allowDoor = true});

  factory RingSettings.fromMap(Map<Object?, Object?> m) {
    final until = m['mutedUntil'];
    return RingSettings(
      enabled: m['enabled'] as bool? ?? true,
      mutedUntil: until is int && until > 0 ? DateTime.fromMillisecondsSinceEpoch(until) : null,
      allowDoor: m['allowDoor'] as bool? ?? true,
    );
  }

  /// The switch position the user chose (off = silent until switched on again).
  final bool enabled;

  /// Silent until this time; null or in the past = not muted.
  final DateTime? mutedUntil;

  /// "Türklingel trotzdem": door-station calls ring even while silent.
  final bool allowDoor;

  Map<String, Object?> toMap() => {
        'enabled': enabled,
        'mutedUntil': mutedUntil?.millisecondsSinceEpoch ?? 0,
        'allowDoor': allowDoor,
      };

  bool isMutedAt(DateTime now) => mutedUntil != null && mutedUntil!.isAfter(now);

  /// Normal calls ring on this handset right now.
  bool ringsAt(DateTime now) => enabled && !isMutedAt(now);

  /// Switch on: ring again (also ends a timed mute).
  RingSettings ringing() => RingSettings(allowDoor: allowDoor);

  /// Switch off: silent until switched on again.
  RingSettings silent() => RingSettings(enabled: false, allowDoor: allowDoor);

  RingSettings mutedTill(DateTime until) => RingSettings(mutedUntil: until, allowDoor: allowDoor);

  RingSettings withAllowDoor(bool value) => RingSettings(enabled: enabled, mutedUntil: mutedUntil, allowDoor: value);

  @override
  bool operator ==(Object other) =>
      other is RingSettings && other.enabled == enabled && other.mutedUntil == mutedUntil && other.allowDoor == allowDoor;

  @override
  int get hashCode => Object.hash(enabled, mutedUntil, allowDoor);
}

/// "17:00", "morgen 8:00", "Mo 8:00" relative to [now].
String formatMuteEnd(DateTime until, DateTime now) {
  final days = _day(until).difference(_day(now)).inDays;
  if (days <= 0) return _hhmm(until);
  if (days == 1) return 'morgen ${_hhmm(until)}';
  const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  return '${weekdays[until.weekday - 1]} ${_hhmm(until)}';
}

/// Short state for the Start pill and the ring card: "Klingelt hier",
/// "Stumm bis 17:00", "Stumm auf diesem Handy".
String ringStateText(RingSettings s, DateTime now) {
  if (s.ringsAt(now)) return 'Klingelt hier';
  if (!s.enabled) return 'Stumm auf diesem Handy';
  return 'Stumm bis ${formatMuteEnd(s.mutedUntil!, now)}';
}

/// Sub-line under "Klingeln auf diesem Handy".
String ringDetailText(RingSettings s, DateTime now) {
  if (s.ringsAt(now)) return 'Tischtelefon und andere Geräte klingeln weiter';
  final base = s.enabled ? 'stumm bis ${formatMuteEnd(s.mutedUntil!, now)}' : 'stumm, bis du es wieder einschaltest';
  return s.allowDoor ? '$base · Türklingel klingelt trotzdem' : base;
}

class MuteOption {
  const MuteOption(this.label, this.until);
  final String label;
  final DateTime until;

  @override
  String toString() => 'MuteOption($label, $until)';
}

/// Next [kMorningHour]:00 after [now] (today if it is still early).
DateTime nextMorning(DateTime now) {
  final today = DateTime(now.year, now.month, now.day, kMorningHour);
  return now.isBefore(today) ? today : DateTime(now.year, now.month, now.day + 1, kMorningHour);
}

/// Quick mute chips: "1 Std", then "bis 17:00" while it is still before 17:00
/// (else "bis 8:00 morgen"), and "bis morgen" (next 8:00) when that is not
/// already the second chip. Night owls before 8:00 get "bis 8:00".
List<MuteOption> muteOptions(DateTime now) {
  final options = <MuteOption>[];
  final evening = DateTime(now.year, now.month, now.day, kEveningHour);
  final morning = nextMorning(now);
  final morningIsToday = morning.day == now.day;
  if (now.isBefore(evening)) {
    options.add(MuteOption('bis $kEveningHour:00', evening));
    options.add(MuteOption(morningIsToday ? 'bis $kMorningHour:00' : 'bis morgen', morning));
  } else {
    options.add(MuteOption('bis $kMorningHour:00 morgen', morning));
  }
  // Before 8:00 "bis 8:00" comes before "bis 17:00"; "1 Std" always first.
  options.sort((a, b) => a.until.compareTo(b.until));
  return [MuteOption('1 Std', now.add(const Duration(hours: 1))), ...options];
}
