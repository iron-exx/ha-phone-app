import 'dart:async';

import 'package:flutter/material.dart';

import '../models/extension_status.dart';
import '../models/presence.dart';
import '../models/ring_settings.dart';
import '../services/api_client.dart';
import '../services/directory_repository.dart';
import '../services/forwarding_repository.dart';
import '../services/presence_repository.dart';
import '../services/ring_settings_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/presence_hint.dart';
import 'nw_widgets.dart';
import 'presence_avatar.dart';

/// "Status und Klingeln" (Nachtwache mockup Status.dc.html), used as the top
/// of the Ich tab and inside the Start pill's sheet:
///  - header: avatar 60, name, "Nebenstelle 18 · HA-Phone x.y.z",
///  - "Status für alle": the PBX presence, four large rows whose sub-line says
///    what happens to calls (from the forwarding rules),
///  - "Nur dieses Handy": the LOCAL switch "Klingeln auf diesem Handy" with quick
///    mute chips and "Türklingel trotzdem",
///  - the forwarding rule of the current status (opens the editor).
class StatusPanel extends StatefulWidget {
  const StatusPanel({
    super.key,
    required this.onOpenForwarding,
    this.showHeader = true,
    DirectoryRepository? directory,
    PresenceRepository? presence,
    ForwardingRepository? forwarding,
    RingSettingsRepository? ring,
  })  : _directory = directory,
        _presence = presence,
        _forwarding = forwarding,
        _ring = ring;

  final VoidCallback onOpenForwarding;
  final bool showHeader;
  final DirectoryRepository? _directory;
  final PresenceRepository? _presence;
  final ForwardingRepository? _forwarding;
  final RingSettingsRepository? _ring;

  @override
  State<StatusPanel> createState() => _StatusPanelState();
}

class _StatusPanelState extends State<StatusPanel> {
  DirectoryRepository get _dir => widget._directory ?? DirectoryRepository.instance;
  PresenceRepository get _pres => widget._presence ?? PresenceRepository.instance;
  ForwardingRepository get _fwd => widget._forwarding ?? ForwardingRepository.instance;
  RingSettingsRepository get _ring => widget._ring ?? RingSettingsRepository.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_fwd.hasLoaded && !_fwd.isLoading) unawaited(_fwd.refresh());
      if (!_ring.hasLoaded) unawaited(_ring.load());
    });
  }

  Presence get _current => _pres.snapshot?.self?.presence ?? _dir.directory?.self?.presence ?? Presence.unknown;

  Future<void> _setPresence(Presence p) async {
    if (p == _current) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _pres.setOwn(p);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Status nicht gespeichert: ${e.message}')));
    }
  }

  Future<void> _setRing(RingSettings next) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _ring.update(next);
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Einstellung nicht gespeichert.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_dir, _pres, _fwd, _ring]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showHeader) _header(context),
          const SectionHeader('Status für alle', padding: EdgeInsets.fromLTRB(20, 8, 20, 6)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final (i, p) in statusChoices(_current).indexed) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _presenceRow(context, p),
                ],
              ],
            ),
          ),
          const SectionHeader('Nur dieses Handy'),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _ringCard(context)),
          Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: _forwardingCard(context)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.nw;
    final d = _dir.directory;
    final self = d?.self;
    final live = _pres.snapshot?.self;
    final status = ExtensionStatus(presence: _current, line: live?.line ?? LineState.unknown);
    final number = self?.number ?? _pres.snapshot?.selfNumber ?? '';
    final version = d?.pbxVersion ?? '';
    final sub = [
      if (number.isNotEmpty) 'Nebenstelle $number' else 'Noch nicht geladen',
      if (version.isNotEmpty) 'HA-Phone $version',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Row(
        children: [
          PresenceAvatar(
            name: self?.name ?? '',
            number: number,
            presence: avatarPresenceFor(status),
            size: 60,
            background: c.blueSoft,
            foreground: c.blueOnSoft,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(self?.displayName ?? 'Eigene Nebenstelle',
                    key: const Key('status-name'), style: NwType.display(24).copyWith(color: c.text)),
                const SizedBox(height: 3),
                Text(sub, key: const Key('status-sub'), style: NwType.meta.copyWith(color: c.faint, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _presenceRow(BuildContext context, Presence p) {
    final c = context.nw;
    final selected = p == _current;
    final kind = avatarPresenceFor(ExtensionStatus(presence: p, line: LineState.idle)) ?? AvatarPresence.available;
    final hint = presenceHint(p, _fwd.hasLoaded ? _fwd.rules : null, _dir.nameFor);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: selected ? c.blue : Colors.transparent),
    );
    final label = p.label[0].toUpperCase() + p.label.substring(1);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $hint',
      onTap: () => _setPresence(p),
      excludeSemantics: true,
      child: Material(
        color: selected ? c.blueSoft : c.raised,
        shape: shape,
        child: InkWell(
          key: ValueKey('status-${p.apiValue}'),
          customBorder: shape,
          onTap: () => _setPresence(p),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 62),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: kind.color(c)),
                    child: Icon(kind.glyph ?? Icons.circle_outlined, size: 18, color: c.ground),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: NwType.rowTitle.copyWith(color: c.text, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(hint, style: NwType.meta.copyWith(color: c.faint, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (selected) ...[const SizedBox(width: 8), Icon(Icons.check_rounded, color: c.blue)],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ringCard(BuildContext context) {
    final c = context.nw;
    final now = _ring.now();
    final options = muteOptions(now);
    final choice = _ring.muteChoice;
    final selectedMute = selectedMuteOption(options, _ring.settings, now,
        chosenLabel: choice?.$1, chosenUntil: choice?.$2);
    final s = _ring.settings;
    final rings = s.ringsAt(now);
    return NwCard(
      key: const Key('ring-card'),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(rings ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                  size: 22, color: rings ? c.answer : c.door),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Klingeln auf diesem Handy',
                        style: NwType.rowTitle.copyWith(color: c.text, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(ringDetailText(s, now),
                        key: const Key('ring-detail'), style: NwType.meta.copyWith(color: c.faint, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: 'Klingeln auf diesem Handy',
                child: Switch(
                  key: const Key('ring-switch'),
                  value: rings,
                  activeColor: Colors.white,
                  activeTrackColor: c.answer,
                  onChanged: (on) => _setRing(on ? s.ringing() : s.silent()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final (i, o) in options.indexed)
                NwChip(
                  key: ValueKey('mute-${o.label}'),
                  label: o.label,
                  icon: i == 0 ? Icons.notifications_off_outlined : null,
                  selected: i == selectedMute,
                  semanticLabel: 'Stumm ${o.label}',
                  onTap: () {
                    _ring.muteChoice = (o.label, o.until);
                    _setRing(s.mutedTill(o.until));
                  },
                ),
            ],
          ),
          Divider(height: 16, color: c.stroke),
          Row(
            children: [
              Icon(Icons.doorbell_outlined, size: 22, color: c.door),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Türklingel trotzdem', style: NwType.rowTitle.copyWith(color: c.text)),
                    const SizedBox(height: 2),
                    Text('Die Türstation klingelt auch, wenn das Handy stumm ist',
                        style: NwType.meta.copyWith(color: c.faint, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: 'Türklingel trotzdem',
                child: Switch(
                  key: const Key('ring-door-switch'),
                  value: s.allowDoor,
                  activeColor: Colors.white,
                  activeTrackColor: c.door,
                  onChanged: (on) => _setRing(s.withAllowDoor(on)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _forwardingCard(BuildContext context) {
    final c = context.nw;
    final p = _current == Presence.unknown ? Presence.available : _current;
    final rule = _fwd.isUnsupported
        ? 'Weiterleitungen braucht HA-Phone 0.7.110'
        : presenceHint(p, _fwd.hasLoaded ? _fwd.rules : null, _dir.nameFor);
    return Semantics(
      button: true,
      label: 'Weiterleitung bei ${p.label}: $rule. Bearbeiten',
      onTap: widget.onOpenForwarding,
      excludeSemantics: true,
      child: NwCard(
        key: const Key('status-forwarding'),
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: widget.onOpenForwarding,
        child: Row(
          children: [
            Icon(Icons.alt_route_rounded, size: 20, color: c.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Bei „${p.label}“: ', style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: rule),
                ]),
                style: NwType.meta.copyWith(color: c.text, fontSize: 13, height: 1.35),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: c.faint),
          ],
        ),
      ),
    );
  }
}
