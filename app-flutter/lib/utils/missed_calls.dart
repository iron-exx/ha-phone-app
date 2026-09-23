import '../services/sip_channel.dart';

/// Missed calls newer than [lastSeen] (the last time the Anrufe tab was
/// opened); all missed calls if the tab was never opened.
int countMissedSince(List<CallHistoryEntry> entries, DateTime? lastSeen) {
  return entries
      .where((e) => e.missed && (lastSeen == null || e.startedAt.isAfter(lastSeen)))
      .length;
}
