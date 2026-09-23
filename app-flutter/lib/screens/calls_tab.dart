import 'dart:async';

import 'package:flutter/material.dart';

import '../services/call_history_store.dart';
import '../services/call_launcher.dart';
import '../services/directory_repository.dart';
import '../widgets/call_history_tile.dart';
import '../widgets/status_message.dart';

/// Anrufe tab: local call history with Alle / Verpasst filter. The shell
/// reloads the store on CallHistoryChangedEvent and whenever this tab
/// becomes visible ([isActive] flips to true).
class CallsTab extends StatefulWidget {
  const CallsTab({super.key, required this.isActive});

  final bool isActive;

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  bool _missedOnly = false;

  CallHistoryStore get _store => CallHistoryStore.instance;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _onVisible();
  }

  @override
  void didUpdateWidget(CallsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _onVisible();
  }

  void _onVisible() {
    unawaited(_store.load().then((_) => _store.markSeen()));
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
              onPressed: _store.entries.isEmpty ? null : _confirmClear,
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
              listenable: Listenable.merge([_store, DirectoryRepository.instance]),
              builder: (context, _) => _buildList(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final entries = _missedOnly ? _store.entries.where((e) => e.missed).toList() : _store.entries;
    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _store.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
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
    final directory = DirectoryRepository.instance;
    return RefreshIndicator(
      onRefresh: _store.load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final e = entries[i];
          return Dismissible(
            key: ValueKey('call-${e.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Theme.of(context).colorScheme.errorContainer,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onErrorContainer),
            ),
            onDismissed: (_) => _store.delete(e.id),
            child: CallHistoryTile(
              entry: e,
              resolvedName: e.name.isNotEmpty ? e.name : directory.nameFor(e.number),
              now: now,
              onTap: () => CallLauncher.call(context, e.number),
            ),
          );
        },
      ),
    );
  }
}
