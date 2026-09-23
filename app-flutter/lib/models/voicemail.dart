/// One mailbox message from GET /api/mobile/voicemail.
class VoicemailMessage {
  const VoicemailMessage({
    required this.id,
    required this.isNew,
    this.callerNumber = '',
    this.callerName = '',
    this.duration = Duration.zero,
    required this.receivedAt,
  });

  factory VoicemailMessage.fromJson(Map<String, dynamic> json) {
    final received = json['received_at'];
    final duration = json['duration_sec'];
    return VoicemailMessage(
      id: (json['id'] ?? '').toString(),
      isNew: json['new'] == true,
      callerNumber: (json['caller_number'] ?? '').toString(),
      callerName: (json['caller_name'] ?? '').toString(),
      duration: Duration(seconds: duration is num ? duration.toInt() : 0),
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        (received is num ? received.toInt() : 0) * 1000,
      ),
    );
  }

  /// "INBOX/msg0000" (INBOX = new, Old = heard).
  final String id;
  final bool isNew;
  final String callerNumber;
  final String callerName;
  final Duration duration;
  final DateTime receivedAt;

  /// Folder and file name for the audio/delete URLs, null if the id is malformed.
  ({String folder, String name})? get path => splitVoicemailId(id);

  /// Asterisk renumbers messages (a new INBOX/msg0000 after the old one moved
  /// to Old), so "heard locally" is keyed by id plus timestamp.
  String get heardKey => '$id@${receivedAt.millisecondsSinceEpoch ~/ 1000}';
}

/// "INBOX/msg0000" -> (folder: INBOX, name: msg0000). Rejects anything that
/// could escape the mailbox path.
({String folder, String name})? splitVoicemailId(String id) {
  final parts = id.split('/');
  if (parts.length != 2) return null;
  final valid = RegExp(r'^[A-Za-z0-9_\-]+$');
  if (!valid.hasMatch(parts[0]) || !valid.hasMatch(parts[1])) return null;
  return (folder: parts[0], name: parts[1]);
}

/// Parsed response of GET /api/mobile/voicemail, newest first.
class VoicemailBox {
  const VoicemailBox({this.messages = const []});

  factory VoicemailBox.fromJson(Map<String, dynamic> json) {
    final raw = json['messages'];
    final messages = raw is List
        ? raw.whereType<Map<String, dynamic>>().map(VoicemailMessage.fromJson).where((m) => m.id.isNotEmpty).toList()
        : <VoicemailMessage>[];
    messages.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return VoicemailBox(messages: messages);
  }

  final List<VoicemailMessage> messages;
}

/// Badge count: new messages not yet played on this device.
int countUnheard(List<VoicemailMessage> messages, Set<String> heardKeys) =>
    messages.where((m) => m.isNew && !heardKeys.contains(m.heardKey)).length;
