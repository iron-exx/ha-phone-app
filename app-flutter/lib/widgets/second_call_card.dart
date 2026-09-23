import 'package:flutter/material.dart';

import '../services/directory_repository.dart';
import '../services/sip_channel.dart';
import '../theme/app_colors.dart';

/// The second line on the call screen: a knocking call (Annehmen / Ablehnen), the
/// held call (Makeln, Verbinden, Konferenz) or the running 3-way conference.
class SecondCallCard extends StatelessWidget {
  const SecondCallCard({
    super.key,
    required this.other,
    required this.conference,
    required this.onAnswerWaiting,
    required this.onRejectWaiting,
    required this.onSwap,
    required this.onTransfer,
    required this.onMerge,
  });

  final CurrentCall other;
  final bool conference;
  final VoidCallback onAnswerWaiting;
  final VoidCallback onRejectWaiting;
  final VoidCallback onSwap;
  final VoidCallback onTransfer;
  final VoidCallback onMerge;

  String get _name => other.name.isNotEmpty ? other.name : DirectoryRepository.instance.nameFor(other.number);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waiting = other.isWaiting;
    final title = waiting
        ? 'Anklopfen: $_name'
        : conference
            ? 'Konferenz mit $_name'
            : 'Gehalten: $_name';
    return Card(
      key: const Key('second-call'),
      margin: EdgeInsets.zero,
      color: waiting ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(waiting ? Icons.ring_volume : (conference ? Icons.groups : Icons.pause_circle),
                    color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (_name != other.number)
                        Text(other.number, style: tabular(theme.textTheme.bodySmall)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (waiting)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('reject-waiting'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.hangup),
                      onPressed: onRejectWaiting,
                      icon: const Icon(Icons.call_end),
                      label: const Text('Ablehnen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('answer-waiting'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.answer),
                      onPressed: onAnswerWaiting,
                      icon: const Icon(Icons.call),
                      label: const Text('Annehmen'),
                    ),
                  ),
                ],
              )
            else if (!conference)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  TextButton.icon(key: const Key('swap'), onPressed: onSwap, icon: const Icon(Icons.swap_calls), label: const Text('Makeln')),
                  TextButton.icon(key: const Key('connect'), onPressed: onTransfer, icon: const Icon(Icons.call_split), label: const Text('Verbinden')),
                  TextButton.icon(key: const Key('merge'), onPressed: onMerge, icon: const Icon(Icons.call_merge), label: const Text('Konferenz')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
