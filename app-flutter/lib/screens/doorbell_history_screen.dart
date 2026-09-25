import 'dart:async';

import 'package:flutter/material.dart';

import '../models/doorbell_event.dart';
import '../services/doorbell_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/nw_widgets.dart';

/// "Klingel-Verlauf": every ring with picture, who answered (or "verpasst") and
/// whether the door was opened. [door] limits the list to one door station.
class DoorbellHistoryScreen extends StatefulWidget {
  const DoorbellHistoryScreen({super.key, this.door, DoorbellRepository? repository}) : _repository = repository;

  final String? door;
  final DoorbellRepository? _repository;

  @override
  State<DoorbellHistoryScreen> createState() => _DoorbellHistoryScreenState();
}

class _DoorbellHistoryScreenState extends State<DoorbellHistoryScreen> {
  DoorbellRepository get _repo => widget._repository ?? DoorbellRepository.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_repo.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return Scaffold(
      appBar: AppBar(),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          final events = _repo.events.where((e) => widget.door == null || e.doorNumber == widget.door).toList();
          return RefreshIndicator(
            onRefresh: _repo.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const PageHeader('Klingel-Verlauf'),
                if (events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _repo.isUnsupported
                          ? 'Deine Anlage kennt den Klingel-Verlauf noch nicht (ab HA-Phone 0.7.126).'
                          : 'Noch hat niemand geklingelt.',
                      style: NwType.meta.copyWith(color: c.muted),
                    ),
                  )
                else
                  for (final e in events)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _EventRow(event: e, repo: _repo),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.repo});

  final DoorbellEvent event;
  final DoorbellRepository repo;

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final today = t.year == now.year && t.month == now.month && t.day == now.day;
    final clock = '${two(t.hour)}:${two(t.minute)}';
    return today ? 'Heute $clock' : '${two(t.day)}.${two(t.month)}. $clock';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final status = event.missed ? 'verpasst' : 'angenommen von ${event.answeredBy}';
    return Semantics(
      button: event.hasImage,
      label: '${event.title}, ${_when(event.startedAt)}, $status${event.doorOpened ? ', Tür geöffnet' : ''}',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('doorbell-${event.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: event.hasImage ? () => _showFull(context) : null,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.stroke),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(width: 96, height: 60, child: _thumb(c)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title,
                        overflow: TextOverflow.ellipsis,
                        style: NwType.rowTitle.copyWith(color: c.text, fontWeight: FontWeight.w800, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(_when(event.startedAt), style: NwType.meta.copyWith(color: c.faint, fontSize: 12)),
                    const SizedBox(height: 2),
                    Wrap(spacing: 8, children: [
                      Text(status,
                          style: NwType.meta.copyWith(color: event.missed ? c.endStrong : c.answer, fontSize: 12)),
                      if (event.doorOpened)
                        Text('Tür geöffnet', style: NwType.meta.copyWith(color: c.door, fontSize: 12)),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(NwColors c) {
    final empty = Container(
      color: c.raised,
      child: Icon(Icons.door_front_door_outlined, color: c.faint, size: 22),
    );
    if (!event.hasImage) return empty;
    return FutureBuilder(
      future: repo.image(event),
      builder: (context, snap) =>
          snap.data == null ? empty : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }

  void _showFull(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(event.title)),
        body: Center(
          child: FutureBuilder(
            future: repo.image(event),
            builder: (context, snap) => snap.data == null
                ? const CircularProgressIndicator()
                : InteractiveViewer(child: Image.memory(snap.data!)),
          ),
        ),
      ),
    ));
  }
}
