/// One ring at a door station (GET /api/mobile/doorbell, HA-Phone 0.7.126+).
class DoorbellEvent {
  const DoorbellEvent({
    required this.id,
    required this.doorNumber,
    required this.doorName,
    required this.startedAt,
    this.answeredBy = '',
    this.doorOpened = false,
    this.hasImage = false,
  });

  factory DoorbellEvent.fromJson(Map<String, dynamic> j) => DoorbellEvent(
        id: (j['id'] as num).toInt(),
        doorNumber: '${j['door_number']}',
        doorName: (j['door_name'] as String?) ?? '',
        startedAt: DateTime.tryParse((j['started_at'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
        answeredBy: (j['answered_by'] as String?) ?? '',
        doorOpened: j['door_opened'] == true,
        hasImage: j['has_image'] == true,
      );

  final int id;
  final String doorNumber;
  final String doorName;
  final DateTime startedAt;
  final String answeredBy;
  final bool doorOpened;
  final bool hasImage;

  bool get missed => answeredBy.isEmpty;
  String get title => doorName.isEmpty ? 'Tür $doorNumber' : doorName;
}

List<DoorbellEvent> parseDoorbellEvents(Object? body) => body is List
    ? body.whereType<Map<String, dynamic>>().map(DoorbellEvent.fromJson).toList()
    : const [];
