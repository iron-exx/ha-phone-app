/// One entry of GET /api/mobile/calls (HA-Phone 0.7.110+): the PBX's call
/// log for the own extension, including calls taken or missed on other
/// devices of the same extension (desk phone).
class PbxCall {
  const PbxCall({
    required this.id,
    required this.number,
    required this.name,
    required this.direction,
    required this.answered,
    required this.startedAt,
    required this.duration,
  });

  factory PbxCall.fromJson(Map<String, dynamic> json) => PbxCall(
        id: (json['id'] ?? '').toString(),
        number: (json['number'] ?? '').toString(),
        name: (json['name'] as String?) ?? '',
        direction: (json['direction'] as String?) ?? '',
        answered: json['answered'] == true,
        startedAt: DateTime.fromMillisecondsSinceEpoch(((json['started_at'] as num?) ?? 0).toInt() * 1000),
        duration: Duration(seconds: ((json['duration_sec'] as num?) ?? 0).toInt()),
      );

  final String id;
  final String number;
  final String name;

  /// 'incoming' | 'outgoing'
  final String direction;
  final bool answered;
  final DateTime startedAt;
  final Duration duration;

  bool get missed => direction == 'incoming' && !answered;
}

/// Parses the {"calls":[...]} body (newest first); entries without id are dropped.
List<PbxCall> parsePbxCalls(Map<String, dynamic> json) {
  final raw = json['calls'];
  if (raw is! List) return const [];
  return raw.whereType<Map<String, dynamic>>().map(PbxCall.fromJson).where((c) => c.id.isNotEmpty).toList();
}
