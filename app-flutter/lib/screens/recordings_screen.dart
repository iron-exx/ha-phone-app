import 'dart:async';

import 'package:flutter/material.dart';

import '../models/recording.dart';
import '../services/api_client.dart';
import '../services/call_launcher.dart';
import '../services/directory_repository.dart';
import '../services/pbx_audio.dart';
import '../services/recordings_repository.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../widgets/audio_player_panel.dart';
import '../widgets/presence_avatar.dart';
import '../widgets/status_message.dart';

/// Call recordings of the own extension ("Ich" → "Aufnahmen"): list with an
/// inline player, delete, pull-to-refresh. Refreshes when opened.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({
    super.key,
    RecordingsRepository? repository,
    DirectoryRepository? directory,
    PbxAudioFactory? audioFactory,
  })  : _repository = repository,
        _directory = directory,
        _audioFactory = audioFactory;

  final RecordingsRepository? _repository;
  final DirectoryRepository? _directory;
  final PbxAudioFactory? _audioFactory;

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  String? _expandedId;

  RecordingsRepository get _repo => widget._repository ?? RecordingsRepository.instance;
  DirectoryRepository get _dir => widget._directory ?? DirectoryRepository.instance;

  @override
  void initState() {
    super.initState();
    // After the first frame: refresh() notifies at once, and the Ich tab's
    // entry below this route listens to the same repository.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_repo.refresh());
    });
  }

  String _nameFor(CallRecording r) => r.peer.isEmpty ? '' : _dir.nameFor(r.peer);

  Future<void> _confirmDelete(CallRecording r) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = _nameFor(r);
    final who = name.isNotEmpty ? name : r.peer;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aufnahme löschen?'),
        content: Text(who.isEmpty
            ? 'Die Aufnahme wird auf der Anlage gelöscht.'
            : 'Die Aufnahme des Gesprächs mit $who wird auf der Anlage gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.nw.endStrong, foregroundColor: ctx.nw.endInk),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(r);
      if (mounted && _expandedId == r.id) setState(() => _expandedId = null);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aufnahmen')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_repo, _dir]),
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final error = _repo.error;
    final recordings = _repo.recordings;
    if (!_repo.hasLoaded && _repo.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (recordings.isEmpty) {
      return _scrollable([
        const SizedBox(height: 48),
        if (error != null) _errorState(error) else _emptyState(),
      ]);
    }
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: _repo.refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: recordings.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return error == null ? const SizedBox.shrink() : ErrorBanner(message: error.message);
          }
          return _row(recordings[i - 1], now);
        },
      ),
    );
  }

  Widget _row(CallRecording r, DateTime now) {
    final expanded = _expandedId == r.id;
    final name = _nameFor(r);
    return Column(
      key: ValueKey('rec-${r.id}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _RecordingTile(
          recording: r,
          resolvedName: name,
          isExpanded: expanded,
          now: now,
          onTap: () => setState(() => _expandedId = expanded ? null : r.id),
        ),
        if (expanded)
          AudioPlayerPanel(
            key: ValueKey('player-${r.id}'),
            source: () => _repo.audioSource(r),
            audioFactory: widget._audioFactory ?? defaultPbxAudio,
            fallbackDuration: r.duration,
            onCallBack: r.peer.isEmpty ? null : () => CallLauncher.call(context, r.peer),
            onDelete: () => _confirmDelete(r),
          ),
      ],
    );
  }

  Widget _scrollable(List<Widget> children) => RefreshIndicator(
        onRefresh: _repo.refresh,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: children),
      );

  Widget _emptyState() => StatusMessage(
        icon: Icons.mic_none,
        message: _repo.isAllowed
            ? 'Keine Aufnahmen\nIm Gespräch auf „Aufnehmen“ tippen.'
            : 'Keine Aufnahmen\nGesprächsaufzeichnung ist für deine Nebenstelle nicht freigegeben.',
      );

  Widget _errorState(ApiException error) {
    if (error.kind == ApiErrorKind.unsupported) {
      return StatusMessage(icon: Icons.system_update_outlined, message: error.message);
    }
    if (error.needsRepairing) {
      return StatusMessage(
        icon: Icons.link_off,
        message: error.message,
        actionLabel: 'Neu koppeln',
        onAction: () async {
          await Navigator.of(context).pushNamed('/qr-scan');
          await _repo.refresh();
        },
      );
    }
    return StatusMessage(
      icon: Icons.cloud_off_outlined,
      message: error.message,
      actionLabel: 'Erneut',
      onAction: _repo.refresh,
    );
  }
}

/// Recording row: avatar, name or number, "3:12 · heute 14:02".
class _RecordingTile extends StatelessWidget {
  const _RecordingTile({
    required this.recording,
    required this.resolvedName,
    required this.isExpanded,
    required this.now,
    required this.onTap,
  });

  final CallRecording recording;

  /// Directory or address-book name of the peer, or ''.
  final String resolvedName;
  final bool isExpanded;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = recording.peer;
    final title = resolvedName.isNotEmpty ? resolvedName : (number.isNotEmpty ? number : 'Unbekannt');
    return ListTile(
      onTap: onTap,
      selected: isExpanded,
      selectedTileColor: theme.colorScheme.primary.withOpacity(0.06),
      leading: PresenceAvatar(name: resolvedName, number: number),
      title: Text(
        title,
        overflow: TextOverflow.ellipsis,
        style: tabular(theme.textTheme.bodyLarge)?.copyWith(color: theme.colorScheme.onSurface),
      ),
      subtitle: Text(
        voicemailSubtitle(recording.duration, recording.startedAt, now),
        style: tabular(theme.textTheme.bodyMedium),
      ),
    );
  }
}
