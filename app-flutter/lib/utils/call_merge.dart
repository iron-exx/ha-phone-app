import '../models/pbx_call.dart';
import '../services/sip_channel.dart';

/// PBX and local entries within this window (same number + direction) are
/// the same call.
const kCallMatchWindow = Duration(seconds: 30);

/// One row of the Anrufe list: a local entry, a PBX entry, or both.
class MergedCall {
  const MergedCall({this.local, this.pbx}) : assert(local != null || pbx != null);

  final CallHistoryEntry? local;
  final PbxCall? pbx;

  String get key => local != null ? 'l-${local!.id}' : 'p-${pbx!.id}';

  String get number => local?.number ?? pbx!.number;

  String get name {
    final l = local?.name ?? '';
    return l.isNotEmpty ? l : (pbx?.name ?? '');
  }

  String get direction => local?.direction ?? pbx!.direction;

  /// Answered on any device of the own extension.
  bool get answered => (local?.answered ?? false) || (pbx?.answered ?? false);

  DateTime get startedAt => local?.startedAt ?? pbx!.startedAt;

  bool get missed => direction == 'incoming' && !answered;

  /// Only the PBX knows it (e.g. rang the desk phone while the app was
  /// offline), or another device answered what rang here unanswered.
  bool get isOtherDevice {
    final p = pbx;
    if (p == null) return false;
    final l = local;
    if (l == null) return true;
    return l.missed && p.answered;
  }

  /// Entry for CallHistoryTile / callSubtitle (answered state merged).
  CallHistoryEntry get entry {
    final l = local;
    final p = pbx;
    if (l != null && (p == null || !isOtherDevice)) return l;
    return CallHistoryEntry(
      id: key,
      number: number,
      name: name,
      direction: direction,
      answered: answered,
      video: l?.video ?? false,
      startedAt: startedAt,
      duration: (l == null || l.duration == Duration.zero) ? p!.duration : l.duration,
    );
  }
}

bool _sameCall(CallHistoryEntry l, PbxCall p) =>
    l.number == p.number &&
    l.direction == p.direction &&
    l.startedAt.difference(p.startedAt).abs() <= kCallMatchWindow;

/// Merges the local history with the PBX log, newest first. Each PBX call
/// pairs with at most one local entry (the closest in time). PBX calls in
/// [hiddenPbxIds] are dropped (deleted on this device).
List<MergedCall> mergeCallHistory(
  List<CallHistoryEntry> local,
  List<PbxCall> pbx, {
  Set<String> hiddenPbxIds = const {},
}) {
  final unmatched = [...local];
  final result = <MergedCall>[];
  for (final p in pbx) {
    if (hiddenPbxIds.contains(p.id)) continue;
    CallHistoryEntry? best;
    for (final l in unmatched) {
      if (!_sameCall(l, p)) continue;
      if (best == null ||
          l.startedAt.difference(p.startedAt).abs() < best.startedAt.difference(p.startedAt).abs()) {
        best = l;
      }
    }
    if (best != null) unmatched.remove(best);
    result.add(MergedCall(local: best, pbx: p));
  }
  result.addAll(unmatched.map((l) => MergedCall(local: l)));
  result.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return result;
}

/// Missed calls (incl. PBX-only ones) newer than [lastSeen]; all if null.
int countMergedMissedSince(List<MergedCall> calls, DateTime? lastSeen) =>
    calls.where((c) => c.missed && (lastSeen == null || c.startedAt.isAfter(lastSeen))).length;
