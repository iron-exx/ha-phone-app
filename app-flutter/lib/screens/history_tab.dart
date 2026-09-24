import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../services/api_client.dart';
import '../services/app_navigation.dart';
import '../services/call_history_store.dart';
import '../services/call_launcher.dart';
import '../services/directory_repository.dart';
import '../services/pbx_audio.dart';
import '../services/presence_repository.dart';
import '../services/recordings_repository.dart';
import '../services/voicemail_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/timeline.dart';
import '../widgets/inline_audio_player.dart';
import '../widgets/nw_widgets.dart';
import '../widgets/presence_avatar.dart';
import '../widgets/status_message.dart';
import '../widgets/timeline_row.dart';

/// Verlauf: one timeline of calls (local + PBX log), voicemails and call
/// recordings, grouped by day, with the filter chips Alle · Verpasst ·
/// Voicemail · Aufnahmen · Tür. Swipe right calls back, swipe left deletes
/// (voicemail/recordings on the PBX after asking). While visible
/// ([isActive]) the call log polls the PBX and missed calls count as seen;
/// rows that were new when the tab opened keep their bar for this visit.
class HistoryTab extends StatefulWidget {
  const HistoryTab({
    super.key,
    required this.isActive,
    CallHistoryStore? store,
    VoicemailRepository? voicemail,
    RecordingsRepository? recordings,
    DirectoryRepository? directory,
    PresenceRepository? presence,
    AppNavigation? navigation,
    PbxAudioFactory? audioFactory,
  })  : _store = store,
        _voicemail = voicemail,
        _recordings = recordings,
        _directory = directory,
        _presence = presence,
        _navigation = navigation,
        _audioFactory = audioFactory;

  final bool isActive;
  final CallHistoryStore? _store;
  final VoicemailRepository? _voicemail;
  final RecordingsRepository? _recordings;
  final DirectoryRepository? _directory;
  final PresenceRepository? _presence;
  final AppNavigation? _navigation;
  final PbxAudioFactory? _audioFactory;

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  TimelineFilter _filter = TimelineFilter.all;
  final _search = TextEditingController();
  bool _searching = false;

  /// Badge state when the tab opened: missed calls after it are "new".
  DateTime? _missedSeenBefore;
  bool _seenCaptured = false;

  /// Rows swiped away whose PBX delete is still running (or failed).
  final Set<String> _removing = {};

  CallHistoryStore get _store => widget._store ?? CallHistoryStore.instance;
  VoicemailRepository get _vm => widget._voicemail ?? VoicemailRepository.instance;
  RecordingsRepository get _rec => widget._recordings ?? RecordingsRepository.instance;
  DirectoryRepository get _dir => widget._directory ?? DirectoryRepository.instance;
  PresenceRepository get _presence => widget._presence ?? PresenceRepository.instance;
  AppNavigation get _nav => widget._navigation ?? AppNavigation.instance;
  PbxAudioFactory get _audio => widget._audioFactory ?? defaultPbxAudio;

  @override
  void initState() {
    super.initState();
    _nav.addListener(_takeFilter);
    _takeFilter();
    if (widget.isActive) _onVisible();
  }

  @override
  void didUpdateWidget(HistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _onVisible();
    if (!widget.isActive && oldWidget.isActive) {
      _store.setVisible(false);
      _seenCaptured = false;
    }
  }

  @override
  void dispose() {
    _nav.removeListener(_takeFilter);
    _store.setVisible(false);
    _search.dispose();
    super.dispose();
  }

  void _takeFilter() {
    final f = _nav.takeHistoryFilter();
    if (f != null && mounted) setState(() => _filter = f);
  }

  void _onVisible() {
    if (!_seenCaptured) {
      _missedSeenBefore = _store.lastSeen;
      _seenCaptured = true;
    }
    // The poller fetches the PBX log right away when it starts.
    _store.setVisible(true);
    unawaited(_store.load());
    // After the first frame: refresh() notifies at once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_vm.refresh());
      unawaited(_rec.refresh());
    });
  }

  Future<void> _refreshAll() => Future.wait([_store.refreshAll(), _vm.refresh(), _rec.refresh()]);

  String _nameFor(TimelineItem i) => i.ownName.isNotEmpty ? i.ownName : _dir.nameFor(i.number);

  Set<String> get _doorNumbers => {
        for (final e in _dir.directory?.extensions ?? const []) if (e.isDoorStation) e.number,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([_store, _vm, _rec, _dir, _presence]),
          builder: (context, _) => _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final all = buildTimeline(
      calls: _store.calls,
      voicemails: _vm.messages,
      recordings: _rec.recordings,
    ).where((i) => !_removing.contains(i.key)).toList();
    final doors = _doorNumbers;
    final items = filterTimeline(all, _filter, doorNumbers: doors, query: _search.text, nameFor: _dir.nameFor);
    final newMissed = all.where((i) => i.isMissedCall && _unread(i)).length;
    return Column(
      children: [
        PageHeader('Verlauf', actions: [
          NwIconButton(
            icon: _searching ? Icons.close : Icons.search,
            label: _searching ? 'Suche schließen' : 'Verlauf durchsuchen',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _search.clear();
            }),
          ),
          _menu(context),
        ]),
        if (_searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Name oder Nummer',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: NwChipRow(children: [
            for (final f in TimelineFilter.values)
              NwChip(
                key: ValueKey('filter-${f.name}'),
                label: f == TimelineFilter.missed && newMissed > 0 ? '${f.label} · $newMissed' : f.label,
                selected: _filter == f,
                onTap: () => setState(() => _filter = f),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshAll,
            child: _list(context, items, doors),
          ),
        ),
      ],
    );
  }

  Widget _menu(BuildContext context) {
    final c = context.nw;
    return PopupMenuButton<String>(
      tooltip: 'Mehr',
      onSelected: (v) {
        if (v == 'mailbox') CallLauncher.call(context, kVoicemailNumber);
        if (v == 'clear') _confirmClear();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'mailbox', child: Text('Mailbox anrufen')),
        PopupMenuItem(
          value: 'clear',
          enabled: _store.calls.isNotEmpty,
          child: const Text('Anrufliste löschen'),
        ),
      ],
      child: Container(
        width: kMinTap,
        height: kMinTap,
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.stroke),
        ),
        child: Icon(Icons.more_horiz, color: c.text, size: 20),
      ),
    );
  }

  bool _unread(TimelineItem i) =>
      isTimelineItemUnread(i, missedSeenBefore: _missedSeenBefore, isUnheard: _vm.isUnheard);

  Widget _list(BuildContext context, List<TimelineItem> items, Set<String> doors) {
    final now = DateTime.now();
    final children = <Widget>[];
    final hint = _hint(context, isEmpty: items.isEmpty);
    if (hint != null) children.add(hint);
    if (items.isEmpty) {
      children.add(const SizedBox(height: 32));
      children.add(_emptyState(context));
    } else {
      String? day;
      for (final i in items) {
        final label = timelineDayLabel(i.at, now);
        if (label != day) {
          day = label;
          children.add(SectionHeader(label));
        }
        children.add(_row(context, i, doors));
      }
      children.add(_swipeHint(context));
    }
    children.add(const SizedBox(height: 24));
    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: children);
  }

  Widget _row(BuildContext context, TimelineItem i, Set<String> doors) {
    final c = context.nw;
    final name = _nameFor(i);
    final isDoor = i.kind != TimelineKind.recording && doors.contains(i.number);
    final isExtension = _dir.directory?.contactFor(i.number)?.isExtension ?? false;
    final canCall = i.number.isNotEmpty;
    final row = TimelineRow(
      item: i,
      name: name,
      isDoor: isDoor,
      isUnread: _unread(i),
      presence: isExtension ? avatarPresenceFor(_presence.statusFor(i.number)) : null,
      extra: _player(i),
      onTap: i.kind == TimelineKind.call && canCall ? () => CallLauncher.call(context, i.number) : null,
    );
    final who = name.isNotEmpty ? name : (i.number.isNotEmpty ? i.number : 'Unbekannt');
    return Semantics(
      customSemanticsActions: {
        if (canCall) CustomSemanticsAction(label: '$who zurückrufen'): () => CallLauncher.call(context, i.number),
        // Same confirmation as the swipe: PBX items can't be restored.
        const CustomSemanticsAction(label: 'Löschen'): () => _confirmAndDelete(i, who),
      },
      child: Dismissible(
        key: ValueKey(i.key),
        direction: canCall ? DismissDirection.horizontal : DismissDirection.endToStart,
        background: _swipeBackground(c.answer, c.answerInk, Icons.call, 'Zurückrufen', Alignment.centerLeft),
        secondaryBackground: _swipeBackground(c.endStrong, c.endInk, Icons.delete_outline, 'Löschen', Alignment.centerRight),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            unawaited(CallLauncher.call(context, i.number));
            return false;
          }
          if (i.kind == TimelineKind.call) return true;
          return _confirmPbxDelete(i, who);
        },
        onDismissed: (_) => _delete(i),
        child: row,
      ),
    );
  }

  Widget _swipeBackground(Color bg, Color fg, IconData icon, String label, Alignment align) => Container(
        color: bg,
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: 8),
            Text(label, style: NwType.button.copyWith(color: fg, fontSize: 14)),
          ],
        ),
      );

  Widget? _player(TimelineItem i) {
    switch (i.kind) {
      case TimelineKind.voicemail:
        final m = i.voicemail!;
        return InlineAudioPlayer(
          key: ValueKey('player-${m.heardKey}'),
          source: () => _vm.audioSource(m),
          audioFactory: _audio,
          fallbackDuration: m.duration,
          seed: m.heardKey.hashCode,
          onPlay: () => unawaited(_vm.markHeard(m)),
          loadErrorText: 'Sprachnachricht konnte nicht geladen werden.',
        );
      case TimelineKind.recording:
        final r = i.recording!;
        return InlineAudioPlayer(
          key: ValueKey('player-${r.id}'),
          source: () => _rec.audioSource(r),
          audioFactory: _audio,
          fallbackDuration: r.duration,
          seed: r.id.hashCode,
        );
      case TimelineKind.call:
        return null;
    }
  }

  Future<bool> _confirmPbxDelete(TimelineItem i, String who) async {
    final c = context.nw;
    final isVm = i.kind == TimelineKind.voicemail;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isVm ? 'Sprachnachricht löschen?' : 'Aufnahme löschen?'),
        content: Text(isVm
            ? 'Die Sprachnachricht von $who wird aus der Mailbox gelöscht.'
            : 'Die Aufnahme des Gesprächs mit $who wird auf der Anlage gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.endStrong, foregroundColor: c.endInk),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _confirmAndDelete(TimelineItem i, String who) async {
    if (i.kind != TimelineKind.call && !await _confirmPbxDelete(i, who)) return;
    if (mounted) await _delete(i);
  }

  /// Calls: gone locally right away. Voicemail/recordings: hidden while the
  /// PBX deletes them; shown again with a SnackBar if that fails.
  Future<void> _delete(TimelineItem i) async {
    if (i.kind == TimelineKind.call) {
      await _store.deleteCall(i.call!);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _removing.add(i.key));
    try {
      if (i.kind == TimelineKind.voicemail) {
        await _vm.delete(i.voicemail!);
      } else {
        await _rec.delete(i.recording!);
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: ${e.message}')));
    } finally {
      if (mounted) setState(() => _removing.remove(i.key));
    }
  }

  Future<void> _confirmClear() async {
    final c = context.nw;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anrufliste löschen?'),
        content: const Text('Alle Anrufe werden auf diesem Gerät aus dem Verlauf gelöscht. '
            'Sprachnachrichten und Aufnahmen bleiben.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.endStrong, foregroundColor: c.endInk),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) await _store.clear();
  }

  /// "Too old" for the call log, else "Anlage nicht erreichbar – Stand hh:mm"
  /// when a source of this filter failed and the list shows older data. An
  /// empty Mailbox/Aufnahmen filter explains its error itself.
  Widget? _hint(BuildContext context, {required bool isEmpty}) {
    final e = _store.pbxError;
    final callsShown = _filter != TimelineFilter.voicemail && _filter != TimelineFilter.recordings;
    if (callsShown && e != null && e.kind == ApiErrorKind.unsupported) {
      return ErrorBanner(message: 'Anrufe anderer Geräte: ${e.message}');
    }
    final failed = <(ApiException?, DateTime?)>[
      if (callsShown) (e, _store.pbxLoadedAt),
      if (_filter == TimelineFilter.all || _filter == TimelineFilter.voicemail || _filter == TimelineFilter.door)
        (_vm.error, _vm.loadedAt),
      if (_filter == TimelineFilter.all || _filter == TimelineFilter.recordings) (_rec.error, _rec.loadedAt),
    ].where((f) => f.$1?.kind == ApiErrorKind.unreachable || f.$1?.kind == ApiErrorKind.server).toList();
    if (failed.isEmpty) return null;
    if (isEmpty && !callsShown) return null;
    final stamps = failed.map((f) => f.$2).toList();
    final stand = stamps.contains(null)
        ? null
        : stamps.whereType<DateTime>().reduce((a, b) => a.isBefore(b) ? a : b);
    return ErrorBanner(
      message: stand == null ? 'Anlage nicht erreichbar' : 'Anlage nicht erreichbar – Stand ${_hhmm(stand)}',
    );
  }

  static String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _emptyState(BuildContext context) {
    if (_search.text.trim().isNotEmpty) {
      return StatusMessage(icon: Icons.search_off, message: 'Keine Treffer für „${_search.text.trim()}“');
    }
    switch (_filter) {
      case TimelineFilter.voicemail:
        final error = _vm.error;
        if (error != null) return _pbxErrorState(error, voicemail: true);
        if (!_vm.hasLoaded && _vm.isLoading) return const Center(child: CircularProgressIndicator());
        return StatusMessage(
          icon: Icons.voicemail,
          message: 'Keine Sprachnachrichten',
          actionLabel: 'Mailbox anrufen',
          onAction: () => CallLauncher.call(context, kVoicemailNumber),
        );
      case TimelineFilter.recordings:
        final error = _rec.error;
        if (error != null) return _pbxErrorState(error, voicemail: false);
        // "nicht freigegeben" only after the PBX said so.
        if (!_rec.hasLoaded) return const Center(child: CircularProgressIndicator());
        return StatusMessage(
          icon: Icons.mic_none,
          message: _rec.isAllowed
              ? 'Keine Aufnahmen\nIm Gespräch auf „Aufnehmen“ tippen.'
              : 'Keine Aufnahmen\nGesprächsaufzeichnung ist für deine Nebenstelle nicht freigegeben.',
        );
      case TimelineFilter.missed:
        return const StatusMessage(icon: Icons.call_missed, message: 'Keine verpassten Anrufe.');
      case TimelineFilter.door:
        return const StatusMessage(icon: Icons.door_front_door_outlined, message: 'Noch nichts von der Tür.');
      case TimelineFilter.all:
        return StatusMessage(icon: Icons.history, message: _store.error ?? 'Noch keine Anrufe.');
    }
  }

  Widget _pbxErrorState(ApiException error, {required bool voicemail}) {
    if (error.kind == ApiErrorKind.unsupported) {
      return StatusMessage(
        icon: Icons.system_update_outlined,
        message: voicemail ? '${error.message}\nBis dahin erreichst du deine Mailbox per Anruf.' : error.message,
        actionLabel: voicemail ? 'Mailbox anrufen' : null,
        onAction: voicemail ? () => CallLauncher.call(context, kVoicemailNumber) : null,
      );
    }
    if (error.needsRepairing) {
      return StatusMessage(
        icon: Icons.link_off,
        message: error.message,
        actionLabel: 'Neu koppeln',
        onAction: () async {
          await Navigator.of(context).pushNamed('/qr-scan');
          await _refreshAll();
        },
      );
    }
    return StatusMessage(
      icon: Icons.cloud_off_outlined,
      message: error.message,
      actionLabel: 'Erneut',
      onAction: voicemail ? _vm.refresh : _rec.refresh,
    );
  }

  Widget _swipeHint(BuildContext context) {
    final c = context.nw;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.stroke),
        ),
        child: Row(
          children: [
            Icon(Icons.swap_horiz, size: 16, color: c.faint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Nach rechts wischen: zurückrufen · nach links: löschen',
                style: NwType.meta.copyWith(color: c.faint, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
