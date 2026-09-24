import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/recording.dart';
import 'package:ha_phone_test/models/voicemail.dart';
import 'package:ha_phone_test/services/app_navigation.dart';
import 'package:ha_phone_test/services/sip_channel.dart';
import 'package:ha_phone_test/utils/call_merge.dart';
import 'package:ha_phone_test/utils/timeline.dart';

final _t0 = DateTime(2026, 9, 24, 12);

MergedCall _call(String id, String number, DateTime at, {bool answered = true, String direction = 'incoming'}) =>
    MergedCall(
      local: CallHistoryEntry(
        id: id,
        number: number,
        name: '',
        direction: direction,
        answered: answered,
        video: false,
        startedAt: at,
        duration: const Duration(seconds: 10),
      ),
    );

VoicemailMessage _vm(String id, String number, DateTime at, {bool isNew = true}) =>
    VoicemailMessage(id: id, isNew: isNew, callerNumber: number, callerName: 'VM $number', receivedAt: at);

CallRecording _rec(String id, String peer, DateTime at) => CallRecording(id: id, peer: peer, startedAt: at);

void main() {
  group('buildTimeline', () {
    test('merges calls, voicemails and recordings newest first', () {
      final items = buildTimeline(
        calls: [_call('c1', '11', _t0), _call('c2', '12', _t0.subtract(const Duration(hours: 2)))],
        voicemails: [_vm('INBOX/msg0000', '16', _t0.subtract(const Duration(hours: 1)))],
        recordings: [_rec('20260924-080000_0171', '0171', _t0.subtract(const Duration(hours: 3)))],
      );
      expect(items.map((i) => i.kind), [
        TimelineKind.call,
        TimelineKind.voicemail,
        TimelineKind.call,
        TimelineKind.recording,
      ]);
      expect(items.map((i) => i.number), ['11', '16', '12', '0171']);
    });

    test('equal times keep calls before voicemails before recordings', () {
      final items = buildTimeline(
        recordings: [_rec('20260924-120000_11', '11', _t0)],
        voicemails: [_vm('INBOX/msg0000', '11', _t0)],
        calls: [_call('c1', '11', _t0)],
      );
      expect(items.map((i) => i.kind), [TimelineKind.call, TimelineKind.voicemail, TimelineKind.recording]);
    });

    test('keys are unique per kind', () {
      final items = buildTimeline(
        calls: [_call('x', '11', _t0)],
        voicemails: [_vm('INBOX/x', '11', _t0)],
        recordings: [_rec('x', '11', _t0)],
      );
      expect(items.map((i) => i.key).toSet(), hasLength(3));
    });

    test('empty input gives an empty timeline', () {
      expect(buildTimeline(), isEmpty);
    });
  });

  group('filterTimeline', () {
    final items = buildTimeline(
      calls: [
        _call('missed', '11', _t0, answered: false),
        _call('door', '16', _t0.subtract(const Duration(minutes: 5)), answered: false),
        _call('out', '12', _t0.subtract(const Duration(minutes: 10)), direction: 'outgoing'),
      ],
      voicemails: [_vm('INBOX/msg0000', '16', _t0.subtract(const Duration(minutes: 20)))],
      recordings: [_rec('20260924-110000_12', '12', _t0.subtract(const Duration(minutes: 30)))],
    );

    List<String> keys(TimelineFilter f, {String query = ''}) => filterTimeline(
          items,
          f,
          doorNumbers: {'16'},
          query: query,
          nameFor: (n) => n == '12' ? 'Büro' : '',
        ).map((i) => i.key).toList();

    test('Alle keeps everything', () {
      expect(keys(TimelineFilter.all), hasLength(5));
    });

    test('Verpasst: only missed calls (door calls included)', () {
      expect(keys(TimelineFilter.missed), ['call-l-missed', 'call-l-door']);
    });

    test('Voicemail and Aufnahmen pick their kind', () {
      expect(keys(TimelineFilter.voicemail), ['vm-INBOX/msg0000@${_epochOf(_t0.subtract(const Duration(minutes: 20)))}']);
      expect(keys(TimelineFilter.recordings), ['rec-20260924-110000_12']);
    });

    test('Tür: calls and voicemails from door stations, never recordings', () {
      expect(keys(TimelineFilter.door), hasLength(2));
      expect(keys(TimelineFilter.door).every((k) => !k.startsWith('rec-')), isTrue);
    });

    test('search matches resolved names and numbers', () {
      expect(keys(TimelineFilter.all, query: 'büro'), ['call-l-out', 'rec-20260924-110000_12']);
      expect(keys(TimelineFilter.all, query: '16'), hasLength(2));
      expect(keys(TimelineFilter.missed, query: 'VM'), isEmpty);
    });
  });

  group('isTimelineItemUnread', () {
    test('missed calls newer than the last visit are unread', () {
      final missed = TimelineItem.ofCall(_call('m', '11', _t0, answered: false));
      expect(isTimelineItemUnread(missed, missedSeenBefore: null), isTrue);
      expect(isTimelineItemUnread(missed, missedSeenBefore: _t0.subtract(const Duration(minutes: 1))), isTrue);
      expect(isTimelineItemUnread(missed, missedSeenBefore: _t0.add(const Duration(minutes: 1))), isFalse);
    });

    test('answered calls and recordings are never unread', () {
      expect(isTimelineItemUnread(TimelineItem.ofCall(_call('a', '11', _t0))), isFalse);
      expect(isTimelineItemUnread(TimelineItem.ofRecording(_rec('r', '11', _t0))), isFalse);
    });

    test('voicemail follows the heard-locally predicate, else the PBX flag', () {
      final vm = TimelineItem.ofVoicemail(_vm('INBOX/msg0000', '11', _t0));
      expect(isTimelineItemUnread(vm), isTrue);
      expect(isTimelineItemUnread(vm, isUnheard: (_) => false), isFalse);
      final old = TimelineItem.ofVoicemail(_vm('Old/msg0000', '11', _t0, isNew: false));
      expect(isTimelineItemUnread(old), isFalse);
    });
  });

  group('historyBadgeCount', () {
    test('adds missed calls and new voicemails', () {
      expect(historyBadgeCount(unseenMissed: 2, unheardVoicemails: 1), 3);
      expect(historyBadgeCount(unseenMissed: 0, unheardVoicemails: 0), 0);
      expect(historyBadgeCount(unseenMissed: -1, unheardVoicemails: 4), 4);
    });
  });

  group('timelineDayLabel', () {
    test('today, yesterday, weekday, date', () {
      expect(timelineDayLabel(_t0, _t0), 'Heute');
      expect(timelineDayLabel(_t0.subtract(const Duration(days: 1)), _t0), 'Gestern');
      expect(timelineDayLabel(DateTime(2026, 9, 21, 9), _t0), 'Montag, 21.09.');
      expect(timelineDayLabel(DateTime(2026, 8, 1, 9), _t0), '01.08.');
      expect(timelineDayLabel(DateTime(2025, 8, 1, 9), _t0), '01.08.2025');
    });
  });

  group('AppNavigation', () {
    test('voicemail route opens Verlauf with the Voicemail filter once', () {
      final nav = AppNavigation();
      expect(nav.handleRoute('voicemail'), isTrue);
      expect(nav.tab, AppTab.history);
      expect(nav.takeHistoryFilter(), TimelineFilter.voicemail);
      expect(nav.takeHistoryFilter(), isNull);
      expect(nav.handleRoute('active_call'), isFalse);
    });

    test('search and favourites requests switch to Kontakte', () {
      final nav = AppNavigation();
      nav.openContactSearch();
      expect(nav.tab, AppTab.contacts);
      expect(nav.contactSearchRequests, 1);
      nav.select(AppTab.start);
      nav.openFavorites();
      expect(nav.takeFavoritesRequest(), isTrue);
      expect(nav.takeFavoritesRequest(), isFalse);
    });
  });
}

int _epochOf(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
