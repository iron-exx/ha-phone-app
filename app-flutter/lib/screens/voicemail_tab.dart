import 'dart:async';

import 'package:flutter/material.dart';

import '../models/voicemail.dart';
import '../services/api_client.dart';
import '../services/call_launcher.dart';
import '../services/directory_repository.dart';
import '../services/pbx_audio.dart';
import '../services/voicemail_repository.dart';
import '../theme/app_colors.dart';
import '../widgets/audio_player_panel.dart';
import '../widgets/status_message.dart';
import '../widgets/voicemail_tile.dart';

/// Mailbox access number (*97 = own mailbox without PIN, HA-Phone 0.7.104).
const kVoicemailNumber = '*97';

/// Visual voicemail: list of mailbox messages with an inline player.
/// Refreshes whenever the tab becomes visible ([isActive] flips to true).
class VoicemailTab extends StatefulWidget {
  const VoicemailTab({
    super.key,
    this.isActive = false,
    VoicemailRepository? repository,
    DirectoryRepository? directory,
    PbxAudioFactory? audioFactory,
  })  : _repository = repository,
        _directory = directory,
        _audioFactory = audioFactory;

  final bool isActive;
  final VoicemailRepository? _repository;
  final DirectoryRepository? _directory;
  final PbxAudioFactory? _audioFactory;

  @override
  State<VoicemailTab> createState() => _VoicemailTabState();
}

class _VoicemailTabState extends State<VoicemailTab> {
  String? _expandedId;

  VoicemailRepository get _repo => widget._repository ?? VoicemailRepository.instance;
  DirectoryRepository get _dir => widget._directory ?? DirectoryRepository.instance;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) unawaited(_repo.refresh());
  }

  @override
  void didUpdateWidget(VoicemailTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) unawaited(_repo.refresh());
  }

  String _nameFor(VoicemailMessage m) => m.callerName.isNotEmpty ? m.callerName : _dir.nameFor(m.callerNumber);

  Future<void> _confirmDelete(VoicemailMessage m) async {
    final messenger = ScaffoldMessenger.of(context);
    final who = _nameFor(m).isNotEmpty ? _nameFor(m) : m.callerNumber;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nachricht löschen?'),
        content: Text(who.isEmpty
            ? 'Die Nachricht wird aus der Mailbox gelöscht.'
            : 'Die Nachricht von $who wird aus der Mailbox gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.hangup),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(m);
      if (mounted && _expandedId == m.id) setState(() => _expandedId = null);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voicemail'),
        actions: [
          IconButton(
            tooltip: 'Mailbox anrufen',
            icon: const Icon(Icons.phone_forwarded_outlined),
            onPressed: () => CallLauncher.call(context, kVoicemailNumber),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_repo, _dir]),
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final error = _repo.error;
    final messages = _repo.messages;
    if (!_repo.hasLoaded && _repo.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (messages.isEmpty) {
      return _scrollable([
        const SizedBox(height: 48),
        if (error != null)
          _errorState(error)
        else
          const StatusMessage(icon: Icons.voicemail, message: 'Keine Nachrichten'),
      ]);
    }
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: _repo.refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: messages.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return error == null ? const SizedBox.shrink() : ErrorBanner(message: error.message);
          }
          return _row(messages[i - 1], now);
        },
      ),
    );
  }

  Widget _row(VoicemailMessage m, DateTime now) {
    final expanded = _expandedId == m.id;
    final name = _nameFor(m);
    return Column(
      key: ValueKey('vm-${m.heardKey}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        VoicemailTile(
          message: m,
          resolvedName: name,
          isUnheard: _repo.isUnheard(m),
          isExpanded: expanded,
          now: now,
          onTap: () => setState(() => _expandedId = expanded ? null : m.id),
        ),
        if (expanded)
          AudioPlayerPanel(
            key: ValueKey('player-${m.heardKey}'),
            source: () => _repo.audioSource(m),
            audioFactory: widget._audioFactory ?? defaultPbxAudio,
            fallbackDuration: m.duration,
            onPlay: () => unawaited(_repo.markHeard(m)),
            loadErrorText: 'Nachricht konnte nicht geladen werden.',
            onCallBack: m.callerNumber.isEmpty ? null : () => CallLauncher.call(context, m.callerNumber),
            onDelete: () => _confirmDelete(m),
          ),
      ],
    );
  }

  Widget _scrollable(List<Widget> children) => RefreshIndicator(
        onRefresh: _repo.refresh,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: children),
      );

  Widget _errorState(ApiException error) {
    if (error.kind == ApiErrorKind.unsupported) {
      return StatusMessage(
        icon: Icons.system_update_outlined,
        message: '${error.message}\nBis dahin erreichen Sie Ihre Mailbox per Anruf.',
        actionLabel: 'Mailbox anrufen',
        onAction: () => CallLauncher.call(context, kVoicemailNumber),
      );
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
