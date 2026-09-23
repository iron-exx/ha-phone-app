import '../services/sip_channel.dart';

const _weekdaysShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

String _two(int n) => n.toString().padLeft(2, '0');

/// Call-history duration: "0:41", "3:12", "1:02:05".
String formatCallDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '$m:${_two(s)}';
}

/// Live in-call timer: "00:07", "02:37", "1:02:05".
String formatCallTimer(Duration d) {
  final safe = d.isNegative ? Duration.zero : d;
  final h = safe.inHours;
  final m = safe.inMinutes.remainder(60);
  final s = safe.inSeconds.remainder(60);
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
}

/// Right-hand time of a history row: "HH:mm" today, "gestern", short
/// weekday within the last 7 days, otherwise "dd.MM.".
String formatHistoryTime(DateTime t, DateTime now) {
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  // Rounded because DST days are 23/25 h long.
  final days = (today.difference(day).inMinutes / (60 * 24)).round();
  if (days <= 0) return '${_two(t.hour)}:${_two(t.minute)}';
  if (days == 1) return 'gestern';
  if (days < 7) return _weekdaysShort[t.weekday - 1];
  return '${_two(t.day)}.${_two(t.month)}.';
}

/// History row subtitle: "eingehend · 3:12", "verpasst · Video", ...
String callSubtitle(CallHistoryEntry e) {
  final String base;
  if (e.missed) {
    base = 'verpasst';
  } else if (e.direction == 'incoming') {
    base = 'eingehend · ${formatCallDuration(e.duration)}';
  } else if (e.answered) {
    base = 'ausgehend · ${formatCallDuration(e.duration)}';
  } else {
    base = 'ausgehend · nicht erreicht';
  }
  return e.video ? '$base · Video' : base;
}

/// Voicemail row time: "heute 14:02", "gestern 09:10", "Mo 14:02" within the
/// last 7 days, otherwise "12.09. 14:02".
String formatVoicemailTime(DateTime t, DateTime now) {
  final clock = '${_two(t.hour)}:${_two(t.minute)}';
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = (today.difference(day).inMinutes / (60 * 24)).round();
  if (days <= 0) return 'heute $clock';
  if (days == 1) return 'gestern $clock';
  if (days < 7) return '${_weekdaysShort[t.weekday - 1]} $clock';
  return '${_two(t.day)}.${_two(t.month)}. $clock';
}

/// Voicemail row subtitle: "0:42 · heute 14:02".
String voicemailSubtitle(Duration duration, DateTime receivedAt, DateTime now) =>
    '${formatCallDuration(duration)} · ${formatVoicemailTime(receivedAt, now)}';
