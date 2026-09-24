import '../models/contact.dart';
import '../models/recording.dart';
import '../models/voicemail.dart';
import 'call_merge.dart';
import 'contact_filter.dart';

/// Filter chips of the Verlauf tab.
enum TimelineFilter {
  all('Alle'),
  missed('Verpasst'),
  voicemail('Mailbox'),
  recordings('Aufnahmen'),
  door('Tür');

  const TimelineFilter(this.label);
  final String label;
}

enum TimelineKind { call, voicemail, recording }

/// One row of the Verlauf timeline: a (merged) call, a voicemail message or
/// a call recording. Exactly one of [call], [voicemail], [recording] is set.
class TimelineItem {
  const TimelineItem.ofCall(MergedCall this.call)
      : kind = TimelineKind.call,
        voicemail = null,
        recording = null;

  const TimelineItem.ofVoicemail(VoicemailMessage this.voicemail)
      : kind = TimelineKind.voicemail,
        call = null,
        recording = null;

  const TimelineItem.ofRecording(CallRecording this.recording)
      : kind = TimelineKind.recording,
        call = null,
        voicemail = null;

  final TimelineKind kind;
  final MergedCall? call;
  final VoicemailMessage? voicemail;
  final CallRecording? recording;

  /// Stable key for list rows / Dismissible.
  String get key => switch (kind) {
        TimelineKind.call => 'call-${call!.key}',
        TimelineKind.voicemail => 'vm-${voicemail!.heardKey}',
        TimelineKind.recording => 'rec-${recording!.id}',
      };

  DateTime get at => switch (kind) {
        TimelineKind.call => call!.startedAt,
        TimelineKind.voicemail => voicemail!.receivedAt,
        TimelineKind.recording => recording!.startedAt,
      };

  /// The other party's number ('' if unknown).
  String get number => switch (kind) {
        TimelineKind.call => call!.number,
        TimelineKind.voicemail => voicemail!.callerNumber,
        TimelineKind.recording => recording!.peer,
      };

  /// Name delivered with the entry itself ('' if none).
  String get ownName => switch (kind) {
        TimelineKind.call => call!.name,
        TimelineKind.voicemail => voicemail!.callerName,
        TimelineKind.recording => '',
      };

  bool get isMissedCall => kind == TimelineKind.call && call!.missed;
}

/// Merges calls, voicemails and recordings into one list, newest first.
/// Ties keep calls before voicemails before recordings (stable).
List<TimelineItem> buildTimeline({
  List<MergedCall> calls = const [],
  List<VoicemailMessage> voicemails = const [],
  List<CallRecording> recordings = const [],
}) {
  final items = [
    ...calls.map(TimelineItem.ofCall),
    ...voicemails.map(TimelineItem.ofVoicemail),
    ...recordings.map(TimelineItem.ofRecording),
  ];
  final indexed = items.indexed.toList()
    ..sort((a, b) {
      final byTime = b.$2.at.compareTo(a.$2.at);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  return [for (final (_, item) in indexed) item];
}

/// Items matching [filter]. [doorNumbers] are the door-station extensions
/// (calls and voicemails from them count as "Tür"). [query] searches name
/// (entry name or [nameFor]) and number.
List<TimelineItem> filterTimeline(
  List<TimelineItem> items,
  TimelineFilter filter, {
  Set<String> doorNumbers = const {},
  String query = '',
  String Function(String number)? nameFor,
}) {
  final byFilter = items.where((i) => switch (filter) {
        TimelineFilter.all => true,
        TimelineFilter.missed => i.isMissedCall,
        TimelineFilter.voicemail => i.kind == TimelineKind.voicemail,
        TimelineFilter.recordings => i.kind == TimelineKind.recording,
        TimelineFilter.door => i.kind != TimelineKind.recording && doorNumbers.contains(i.number),
      });
  if (query.trim().isEmpty) return byFilter.toList();
  final hits = <TimelineItem>[];
  for (final i in byFilter) {
    final name = i.ownName.isNotEmpty ? i.ownName : (nameFor?.call(i.number) ?? '');
    final asContact = Contact(number: i.number, name: name, isExtension: false);
    if (filterContacts([asContact], query).isNotEmpty) hits.add(i);
  }
  return hits;
}

/// Unread = colour bar + bold: a missed call newer than [missedSeenBefore]
/// (the badge state when the Verlauf was opened; all missed if null), or a
/// voicemail [isUnheard] says is new.
bool isTimelineItemUnread(
  TimelineItem item, {
  DateTime? missedSeenBefore,
  bool Function(VoicemailMessage m)? isUnheard,
}) =>
    switch (item.kind) {
      TimelineKind.call => item.call!.missed && (missedSeenBefore == null || item.at.isAfter(missedSeenBefore)),
      TimelineKind.voicemail => isUnheard?.call(item.voicemail!) ?? item.voicemail!.isNew,
      TimelineKind.recording => false,
    };

/// Badge on the Verlauf tab: new missed calls plus unheard voicemails.
int historyBadgeCount({required int unseenMissed, required int unheardVoicemails}) =>
    (unseenMissed < 0 ? 0 : unseenMissed) + (unheardVoicemails < 0 ? 0 : unheardVoicemails);

/// Day header of a timeline group: "Heute", "Gestern", "Montag, 21.09.".
String timelineDayLabel(DateTime t, DateTime now) {
  const weekdays = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = (today.difference(day).inMinutes / (60 * 24)).round();
  if (days <= 0) return 'Heute';
  if (days == 1) return 'Gestern';
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${two(t.day)}.${two(t.month)}.';
  return days < 7 ? '${weekdays[t.weekday - 1]}, $date' : (t.year == now.year ? date : '$date${t.year}');
}
