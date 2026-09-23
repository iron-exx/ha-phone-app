import 'dart:async';

import 'package:flutter/material.dart';

import '../models/forwarding.dart';
import '../models/presence.dart';
import '../services/api_client.dart';
import '../services/directory_repository.dart';
import '../services/forwarding_repository.dart';
import '../services/presence_repository.dart';
import '../widgets/forwarding_editor_sheet.dart';
import '../widgets/presence_sheet.dart';
import '../widgets/status_message.dart';

/// Ich → Weiterleitungen: per presence status what happens to internal and
/// external calls. The card of the current own status is marked "Aktiv".
class ForwardingScreen extends StatefulWidget {
  const ForwardingScreen({
    super.key,
    ForwardingRepository? repository,
    DirectoryRepository? directory,
    PresenceRepository? presence,
  })  : _repository = repository,
        _directory = directory,
        _presence = presence;

  final ForwardingRepository? _repository;
  final DirectoryRepository? _directory;
  final PresenceRepository? _presence;

  @override
  State<ForwardingScreen> createState() => _ForwardingScreenState();
}

class _ForwardingScreenState extends State<ForwardingScreen> {
  ForwardingRepository get _repo => widget._repository ?? ForwardingRepository.instance;
  DirectoryRepository get _dir => widget._directory ?? DirectoryRepository.instance;
  PresenceRepository get _pres => widget._presence ?? PresenceRepository.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_repo.refresh());
  }

  String get _ownNumber => _dir.directory?.self?.number ?? _pres.snapshot?.selfNumber ?? '';

  Presence? get _currentPresence => _pres.snapshot?.self?.presence ?? _dir.directory?.self?.presence;

  Future<void> _edit(Presence status, ForwardDirection direction, ForwardingRule? rule) async {
    final messenger = ScaffoldMessenger.of(context);
    if (rule != null && rule.isRingGroup) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Weiterleitung zur Klingelgruppe lässt sich nur in der Anlage ändern.'),
      ));
      return;
    }
    final own = _ownNumber;
    final extensions = (_dir.directory?.extensions ?? const []).where((c) => c.number != own).toList();
    final edit = await ForwardingEditorSheet.show(
      context,
      title: '${status.label} · ${direction.label}',
      status: status.apiValue,
      direction: direction,
      rule: rule,
      extensions: extensions,
      ownNumber: own,
    );
    if (edit == null) return;
    try {
      await _repo.setRule(status.apiValue, direction, edit.rule);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Weiterleitung nicht gespeichert: ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weiterleitungen')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_repo, _dir, _pres]),
        builder: (context, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final error = _repo.error;
    if (!_repo.hasLoaded) {
      if (error == null) return const Center(child: CircularProgressIndicator());
      return RefreshIndicator(
        onRefresh: _repo.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 48),
            StatusMessage(
              icon: Icons.phone_forwarded_outlined,
              message: error.message,
              actionLabel: _repo.isUnsupported ? null : 'Erneut versuchen',
              onAction: _repo.isUnsupported ? null : _repo.refresh,
            ),
          ],
        ),
      );
    }
    final current = _currentPresence;
    return RefreshIndicator(
      onRefresh: _repo.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (error != null) ...[
            ErrorBanner(message: error.message, actionLabel: 'Erneut', onAction: _repo.refresh),
            const SizedBox(height: 8),
          ],
          Text(
            'Was mit Anrufen passiert, je nach deinem Status.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          for (final p in kSelectablePresences) _card(context, p, isActive: p == current),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Presence status, {required bool isActive}) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('forward-card-${status.apiValue}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: status.color),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(status.label, style: theme.textTheme.titleMedium)),
                if (isActive)
                  Chip(
                    label: const Text('Aktiv'),
                    visualDensity: VisualDensity.compact,
                    labelStyle: TextStyle(color: theme.colorScheme.onPrimary),
                    backgroundColor: theme.colorScheme.primary,
                    side: BorderSide.none,
                  ),
              ],
            ),
          ),
          for (final d in ForwardDirection.values) _row(context, status, d),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Presence status, ForwardDirection direction) {
    final rule = ruleFor(_repo.rules, status.apiValue, direction);
    final readOnly = rule?.isRingGroup ?? false;
    return ListTile(
      key: ValueKey('forward-${status.apiValue}-${direction.apiValue}'),
      enabled: !_repo.isSaving,
      title: Text(direction.label),
      subtitle: Text(describeRule(rule, _dir.nameFor)),
      trailing: Icon(readOnly ? Icons.lock_outline : Icons.chevron_right),
      onTap: () => _edit(status, direction, rule),
    );
  }
}
