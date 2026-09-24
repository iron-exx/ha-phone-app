import 'dart:async';

import 'package:flutter/material.dart';

import '../models/extension_status.dart';
import '../models/forwarding.dart';
import '../models/presence.dart';
import '../services/api_client.dart';
import '../services/directory_repository.dart';
import '../services/forwarding_repository.dart';
import '../services/presence_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/forwarding_editor_sheet.dart';
import '../widgets/presence_avatar.dart';
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
            style: NwType.meta.copyWith(color: context.nw.muted, fontSize: 14),
          ),
          const SizedBox(height: 8),
          for (final p in kSelectablePresences) _card(context, p, isActive: p == current),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Presence status, {required bool isActive}) {
    final c = context.nw;
    // Same glyph as the status rows: colour + shape, never colour alone.
    final kind = avatarPresenceFor(ExtensionStatus(presence: status, line: LineState.idle)) ?? AvatarPresence.available;
    final label = status.label[0].toUpperCase() + status.label.substring(1);
    return Container(
      key: ValueKey('forward-card-${status.apiValue}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? c.blue : c.stroke, width: isActive ? 2 : 1),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Container(
                    key: ValueKey('forward-glyph-${status.apiValue}'),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: kind.color(c)),
                    child: Icon(kind.glyph ?? Icons.circle_outlined, size: 16, color: c.ground),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label, style: NwType.rowTitle.copyWith(color: c.text, fontWeight: FontWeight.w800)),
                  ),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: c.blueSoft, borderRadius: BorderRadius.circular(12)),
                      child: Text('Aktiv',
                          style: NwType.meta.copyWith(color: c.blueOnSoft, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                ],
              ),
            ),
            for (final d in ForwardDirection.values) _row(context, status, d),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Presence status, ForwardDirection direction) {
    final c = context.nw;
    final rule = ruleFor(_repo.rules, status.apiValue, direction);
    final readOnly = rule?.isRingGroup ?? false;
    return ListTile(
      key: ValueKey('forward-${status.apiValue}-${direction.apiValue}'),
      enabled: !_repo.isSaving,
      title: Text(direction.label, style: NwType.rowTitle.copyWith(color: c.text)),
      subtitle: Text(describeRule(rule, _dir.nameFor), style: NwType.meta.copyWith(color: c.muted)),
      trailing: Icon(readOnly ? Icons.lock_outline : Icons.chevron_right, color: c.faint),
      onTap: () => _edit(status, direction, rule),
    );
  }
}
