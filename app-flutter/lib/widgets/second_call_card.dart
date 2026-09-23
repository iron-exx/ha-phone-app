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

  String get _name {
    if (other.name.isNotEmpty) return other.name;
    final fromDirectory = DirectoryRepository.instance.nameFor(other.number);
    return fromDirectory.isNotEmpty ? fromDirectory : other.number;
  }

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
                children: [
                  _LineAction(key: const Key('swap'), icon: Icons.swap_calls, label: 'Makeln', onPressed: onSwap),
                  _LineAction(key: const Key('connect'), icon: Icons.call_split, label: 'Verbinden', onPressed: onTransfer),
                  _LineAction(key: const Key('merge'), icon: Icons.call_merge, label: 'Konferenz', onPressed: onMerge),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Icon above label so three actions fit side by side even on narrow phones.
class _LineAction extends StatelessWidget {
  const _LineAction({super.key, required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600), maxLines: 1),
            ],
          ),
        ),
      ),
    );
  }
}
