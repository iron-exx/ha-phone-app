import '../models/doorbell_event.dart';
import 'call_merge.dart';

/// Counts for the "Heute" strip on the Start tab.
class TodaySummary {
  const TodaySummary({this.calls = 0, this.missed = 0, this.doorRings = 0});

  final int calls;
  final int missed;
  final int doorRings;

  bool get isEmpty => calls == 0 && doorRings == 0;
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Calls, missed calls and door rings since midnight of [now].
TodaySummary todaySummary(List<MergedCall> calls, List<DoorbellEvent> rings, DateTime now) {
  final today = calls.where((c) => _sameDay(c.startedAt, now)).toList();
  return TodaySummary(
    calls: today.length,
    missed: today.where((c) => c.missed).length,
    doorRings: rings.where((r) => _sameDay(r.startedAt, now)).length,
  );
}

/// Favourite suggestions while there are none: the most called numbers
/// (ties: the most recent first), without [exclude] (self, doors) and
/// service codes such as `*43`.
List<String> suggestFavorites(List<MergedCall> calls, {Set<String> exclude = const {}, int limit = 4}) {
  final count = <String, int>{};
  final latest = <String, DateTime>{};
  for (final c in calls) {
    final n = c.number;
    if (n.isEmpty || n.startsWith('*') || exclude.contains(n)) continue;
    count[n] = (count[n] ?? 0) + 1;
    final seen = latest[n];
    if (seen == null || c.startedAt.isAfter(seen)) latest[n] = c.startedAt;
  }
  final numbers = count.keys.toList()
    ..sort((a, b) {
      final byCount = count[b]!.compareTo(count[a]!);
      return byCount != 0 ? byCount : latest[b]!.compareTo(latest[a]!);
    });
  return numbers.take(limit).toList();
}
