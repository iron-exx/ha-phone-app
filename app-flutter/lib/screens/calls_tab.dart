import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/call_history_store.dart';
import '../services/call_launcher.dart';
import '../services/directory_repository.dart';
import '../utils/call_merge.dart';
import '../widgets/call_history_tile.dart';
import '../widgets/status_message.dart';

/// Anrufe tab: local call history merged with the PBX log (calls on the
/// desk phone too), Alle / Verpasst filter. While visible ([isActive]) the
/// store polls the PBX every 60 s; the shell reloads the local part on
/// CallHistoryChangedEvent.
class CallsTab extends StatefulWidget {
  const CallsTab({super.key, required this.isActive, CallHistoryStore? store, DirectoryRepository? directory})
      : _store = store,
        _directory = directory;

  final bool isActive;
  final CallHistoryStore? _store;
  final DirectoryRepository? _directory;

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  bool _missedOnly = false;

  CallHistoryStore get _store => widget._store ?? CallHistoryStore.instance;
  DirectoryRepository get _directory => widget._directory ?? DirectoryRepository.instance;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _onVisible();
  }

  @override
  void didUpdateWidget(CallsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _onVisible();
    if (!widget.isActive && oldWidget.isActive) _store.setVisible(false);
  }

  @override
  void dispose() {
    _store.setVisible(false);
    super.dispose();
  }

  /// The poller fetches the PBX log right away when it starts.
  void _onVisible() {
    _store.setVisible(true);
    unawaited(_store.load());
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verlauf löschen?'),
        content: const Text('Alle Einträge der Anrufliste werden auf diesem Gerät gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) await _store.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anrufe'),
        actions: [
          ListenableBuilder(
            listenable: _store,
            builder: (context, _) => IconButton(
              tooltip: 'Verlauf löschen',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _store.calls.isEmpty ? null : _confirmClear,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Alle')),
                  ButtonSegment(value: true, label: Text('Verpasst')),
                ],
                selected: {_missedOnly},
                onSelectionChanged: (s) => setState(() => _missedOnly = s.first),
              ),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([_store, _directory]),
              builder: (context, _) => _buildList(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Only "too old" is worth a hint; offline PBX just shows local entries.
  String? _pbxHint() {
    final e = _store.pbxError;
    if (e == null || e.kind != ApiErrorKind.unsupported) return null;
    return 'Anrufe anderer Geräte: ${e.message}';
  }

  Widget _buildList(BuildContext context) {
    final all = _store.calls;
    final calls = _missedOnly ? all.where((c) => c.missed).toList() : all;
    final hint = _pbxHint();
    if (calls.isEmpty) {
      return RefreshIndicator(
        onRefresh: _store.refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (hint != null) ErrorBanner(message: hint),
            const SizedBox(height: 48),
            StatusMessage(
              icon: _missedOnly ? Icons.call_missed : Icons.history,
              message: _store.error ?? (_missedOnly ? 'Keine verpassten Anrufe.' : 'Noch keine Anrufe.'),
            ),
          ],
        ),
      );
    }
    final now = DateTime.now();
    final offset = hint == null ? 0 : 1;
    return RefreshIndicator(
      onRefresh: _store.refreshAll,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: calls.length + offset,
        itemBuilder: (context, i) {
          if (i < offset) return ErrorBanner(message: hint!);
          return _row(context, calls[i - offset], now);
        },
      ),
    );
  }

  Widget _row(BuildContext context, MergedCall c, DateTime now) {
    final entry = c.entry;
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('call-${c.key}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => _store.deleteCall(c),
      child: CallHistoryTile(
        entry: entry,
        resolvedName: entry.name.isNotEmpty ? entry.name : _directory.nameFor(entry.number),
        now: now,
        otherDevice: c.isOtherDevice,
        onTap: () => CallLauncher.call(context, entry.number),
      ),
    );
  }
}
