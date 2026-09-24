/// One call recording from GET /api/mobile/recordings (HA-Phone 0.7.114).
class CallRecording {
  const CallRecording({
    required this.id,
    this.peer = '',
    required this.startedAt,
    this.duration = Duration.zero,
    this.sizeBytes = 0,
  });

  factory CallRecording.fromJson(Map<String, dynamic> json) {
    final started = json['started_at'];
    final duration = json['duration_sec'];
    final size = json['size_bytes'];
    return CallRecording(
      id: (json['id'] ?? '').toString(),
      peer: (json['peer'] ?? '').toString(),
      startedAt: DateTime.fromMillisecondsSinceEpoch((started is num ? started.toInt() : 0) * 1000),
      duration: Duration(seconds: duration is num ? duration.toInt() : 0),
      sizeBytes: size is num ? size.toInt() : 0,
    );
  }

  /// "20260924-101500_0171123": start time on the PBX + the other party.
  final String id;

  /// Number of the other party, '' if the PBX didn't know it.
  final String peer;
  final DateTime startedAt;
  final Duration duration;
  final int sizeBytes;
}

final _recordingId = RegExp(r'^\d{8}-\d{6}_[0-9+*#]{0,32}$');

/// Only ids shaped like the PBX's own file names reach the audio/delete
/// URLs, so nothing can escape the recordings folder.
bool isValidRecordingId(String id) => _recordingId.hasMatch(id);

/// Remote number for the `peer` field: trimmed and cut to the PBX's
/// 32-character limit (longer values would be rejected with 422).
String recordingPeer(String number) {
  final trimmed = number.trim();
  return trimmed.length > 32 ? trimmed.substring(0, 32) : trimmed;
}

/// Parsed response of GET /api/mobile/recordings, newest first.
class RecordingList {
  const RecordingList({this.allowed = false, this.recordings = const []});

  factory RecordingList.fromJson(Map<String, dynamic> json) {
    final raw = json['recordings'];
    final recordings = raw is List
        ? raw.whereType<Map<String, dynamic>>().map(CallRecording.fromJson).where((r) => r.id.isNotEmpty).toList()
        : <CallRecording>[];
    recordings.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return RecordingList(allowed: json['allowed'] == true, recordings: recordings);
  }

  /// The admin allows recording for the own extension.
  final bool allowed;
  final List<CallRecording> recordings;
}

/// Identifies one line of the current call: a later call to the same number
/// is a different line (new answer time), so a recording never carries over.
String recordingLineKey(String number, DateTime? connectedAt) =>
    '$number@${connectedAt?.millisecondsSinceEpoch ?? 0}';

/// Lines of the current call that are being recorded (line key -> start of
/// the recording). Immutable. Nothing needs to be stopped on hang-up: the
/// PBX ends MixMonitor with the channel.
class RecordingLines {
  const RecordingLines([this._since = const {}]);

  final Map<String, DateTime> _since;

  bool get isEmpty => _since.isEmpty;

  /// Start of the recording on [lineKey], null if that line isn't recorded.
  DateTime? since(String lineKey) => _since[lineKey];

  RecordingLines started(String lineKey, DateTime at) => RecordingLines({..._since, lineKey: at});

  RecordingLines stopped(String lineKey) =>
      _since.containsKey(lineKey) ? RecordingLines({..._since}..remove(lineKey)) : this;

  /// Drops lines that are no longer part of the call.
  RecordingLines retain(Set<String> lineKeys) {
    if (_since.keys.every(lineKeys.contains)) return this;
    return RecordingLines({
      for (final e in _since.entries)
        if (lineKeys.contains(e.key)) e.key: e.value,
    });
  }
}
