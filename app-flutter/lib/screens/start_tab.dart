import 'dart:async';

import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../models/directory.dart';
import '../models/extension_status.dart';
import '../models/presence.dart';
import '../models/ring_settings.dart';
import '../models/voicemail.dart';
import '../services/app_navigation.dart';
import '../services/call_history_store.dart';
import '../services/call_launcher.dart';
import '../services/directory_repository.dart';
import '../services/doorbell_repository.dart';
import '../services/door_opener.dart';
import '../services/favorites_store.dart';
import '../services/phone_contacts_repository.dart';
import '../services/presence_repository.dart';
import '../services/forwarding_repository.dart';
import '../services/reachability_repository.dart';
import '../services/registration_watcher.dart';
import '../services/ring_settings_repository.dart';
import '../services/voicemail_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/contact_filter.dart';
import '../utils/formatters.dart';
import '../utils/registration_ui.dart';
import '../utils/timeline.dart';
import '../utils/today.dart';
import '../widgets/call_flip_card.dart';
import '../widgets/contact_details_sheet.dart';
import '../widgets/door_card.dart';
import '../widgets/nw_widgets.dart';
import '../widgets/presence_avatar.dart';
import '../widgets/status_sheet.dart';

/// Text of the Start status pill: where calls ring ([ring], from
/// [ringStateText]: "Klingelt hier" / "Stumm bis 17:00") and the own status.
String startPillText(RegistrationUi registration, Presence presence, {String ring = 'Klingelt hier'}) =>
    switch (registration) {
      RegistrationUi.online => presence == Presence.unknown ? ring : '$ring · ${presence.label}',
      RegistrationUi.connecting => 'Verbinde mit der Anlage…',
      RegistrationUi.offline => 'Nicht verbunden',
    };

/// Start: own status (pill opens the status sheet), search, door stations
/// with "Tür öffnen" (webhook) or "Tür anrufen" and their Home Assistant actions, the "Heute" strip,
/// the call-flip offer, favourites with live presence (or suggestions from the Verlauf while there
/// are none) and a "Neue Voicemail" card.
class StartTab extends StatelessWidget {
  const StartTab({
    super.key,
    DirectoryRepository? directory,
    PresenceRepository? presence,
    VoicemailRepository? voicemail,
    CallHistoryStore? history,
    PhoneContactsRepository? phoneContacts,
    RegistrationWatcher? registration,
    AppNavigation? navigation,
    RingSettingsRepository? ring,
    DoorbellRepository? doorbell,
    this.reachability,
    this.forwarding,
    this.doorActionRunner,
    this.doorOpener,
  })  : _directory = directory,
        _presence = presence,
        _voicemail = voicemail,
        _history = history,
        _phone = phoneContacts,
        _registration = registration,
        _navigation = navigation,
        _ringRepo = ring,
        _doorbell = doorbell;

  final DirectoryRepository? _directory;
  final RingSettingsRepository? _ringRepo;
  final DoorbellRepository? _doorbell;

  /// Seams for the status sheet (default: the singletons).
  final ReachabilityRepository? reachability;
  final ForwardingRepository? forwarding;
  final PresenceRepository? _presence;
  final VoicemailRepository? _voicemail;
  final CallHistoryStore? _history;
  final PhoneContactsRepository? _phone;
  final RegistrationWatcher? _registration;
  final AppNavigation? _navigation;

  /// Door-action seam for tests (default: native runDoorAction).
  final DoorActionRunner? doorActionRunner;

  /// Door webhook seam for tests (default: [DoorOpener.instance]).
  final DoorOpener? doorOpener;

  DirectoryRepository get _dir => _directory ?? DirectoryRepository.instance;
  PresenceRepository get _pres => _presence ?? PresenceRepository.instance;
  VoicemailRepository get _vm => _voicemail ?? VoicemailRepository.instance;
  CallHistoryStore get _calls => _history ?? CallHistoryStore.instance;
  PhoneContactsRepository get _phoneContacts => _phone ?? PhoneContactsRepository.instance;
  RegistrationWatcher get _reg => _registration ?? RegistrationWatcher.instance;
  AppNavigation get _nav => _navigation ?? AppNavigation.instance;
  RingSettingsRepository get _ring => _ringRepo ?? RingSettingsRepository.instance;
  DoorbellRepository get _bell => _doorbell ?? DoorbellRepository.instance;

  Future<void> _refresh() => Future.wait([_dir.refresh(), _pres.refresh(), _vm.refresh()]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([_dir, _pres, _vm, _calls, _reg, _phoneContacts, _ring, _bell, FavoritesStore.instance]),
          builder: (context, _) => RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _header(context),
                _today(context),
                CallFlipCard(presence: _pres),
                ..._doorCards(context),
                ..._favorites(context),
                _voicemailCard(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.nw;
    final self = _dir.directory?.self;
    final live = _pres.snapshot?.self;
    final presence = live?.presence ?? self?.presence ?? Presence.unknown;
    final status = ExtensionStatus(presence: presence, line: live?.line ?? LineState.unknown);
    final kind = avatarPresenceFor(ExtensionStatus(presence: presence, line: LineState.idle));
    final reg = _reg.state;
    final rings = _ring.ringsNow;
    final pill = startPillText(reg, presence, ring: ringStateText(_ring.settings, _ring.now()));
    final (Color bg, Color fg) = switch (reg) {
      RegistrationUi.offline => (c.end.withOpacity(0.14), c.end),
      RegistrationUi.connecting => (c.raised, c.muted),
      RegistrationUi.online when !rings => (c.raised, c.text),
      RegistrationUi.online => switch (kind) {
          AvatarPresence.available || null => (c.okSurface, c.okText),
          AvatarPresence.away => (c.doorSoft, c.door),
          _ => (c.end.withOpacity(0.14), c.end),
        },
    };
    final who = self == null ? 'Eigene Nebenstelle' : '${self.displayName} · ${self.number}';
    void openStatus() => StatusSheet.show(context,
        directory: _dir, presence: _pres, ring: _ring, reachability: reachability, forwarding: forwarding);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
      child: Row(
        children: [
          PresenceAvatar(
            name: self?.name ?? '',
            number: self?.number ?? '',
            presence: avatarPresenceFor(status),
            size: 44,
            background: c.blueSoft,
            foreground: c.blueOnSoft,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              button: true,
              label: '$who, $pill',
              hint: 'Status und Klingeln',
              // excludeSemantics drops the InkWell's action, so TalkBack needs it here.
              onTap: openStatus,
              excludeSemantics: true,
              child: InkWell(
                key: const Key('start-status'),
                borderRadius: BorderRadius.circular(14),
                onTap: openStatus,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kMinTap),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(who,
                          style: NwType.rowTitle.copyWith(color: c.muted, fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                reg != RegistrationUi.online
                                    ? Icons.sync_problem
                                    : rings
                                        ? Icons.notifications_active_outlined
                                        : Icons.notifications_off_outlined,
                                key: Key(rings ? 'start-pill-bell' : 'start-pill-bell-off'),
                                size: 14,
                                color: fg),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                pill,
                                key: const Key('start-pill'),
                                style: NwType.chip.copyWith(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5),
                              ),
                            ),
                            Icon(Icons.chevron_right, size: 16, color: fg),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          NwIconButton(icon: Icons.search, label: 'Kontakte suchen', onPressed: _nav.openContactSearch),
        ],
      ),
    );
  }

  Widget _today(BuildContext context) {
    final t = todaySummary(_calls.calls, _bell.events, DateTime.now());
    if (t.isEmpty) return const SizedBox.shrink();
    final c = context.nw;
    return Padding(
      key: const Key('start-today'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Heute', style: NwType.chip.copyWith(color: c.faint, fontWeight: FontWeight.w800)),
          if (t.calls > 0)
            NwChip(
              key: const Key('today-calls'),
              icon: Icons.call_outlined,
              label: t.calls == 1 ? '1 Anruf' : '${t.calls} Anrufe',
              onTap: () => _nav.openHistory(),
            ),
          if (t.missed > 0)
            NwChip(
              key: const Key('today-missed'),
              icon: Icons.call_missed,
              label: '${t.missed} verpasst',
              foreground: c.end,
              onTap: () => _nav.openHistory(TimelineFilter.missed),
            ),
          if (t.doorRings > 0)
            NwChip(
              key: const Key('today-door'),
              icon: Icons.doorbell_outlined,
              label: '${t.doorRings}× geklingelt',
              foreground: c.door,
              onTap: () => _nav.openHistory(TimelineFilter.door),
            ),
        ],
      ),
    );
  }

  List<Widget> _doorCards(BuildContext context) {
    final doors = _dir.directory?.extensions.where((e) => e.isDoorStation).toList() ?? const <Contact>[];
    return [
      for (final d in doors)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: DoorCard(door: d, lastRing: _lastCallFrom(d.number), runAction: doorActionRunner, opener: doorOpener),
        ),
    ];
  }

  DateTime? _lastCallFrom(String number) {
    for (final c in _calls.calls) {
      if (c.number == number && c.direction == 'incoming') return c.startedAt;
    }
    return null;
  }

  List<Widget> _favorites(BuildContext context) {
    final c = context.nw;
    final d = _dir.directory;
    final favs = resolveFavorites(
      FavoritesStore.instance.numbers,
      extensions: d?.extensions ?? const [],
      phonebook: d?.phonebook ?? const [],
      phone: _phoneContacts.contacts ?? const [],
      self: d?.self?.number,
    );
    final header = SectionHeader(
      'Favoriten',
      trailing: TextButton(
        onPressed: _nav.openFavorites,
        style: TextButton.styleFrom(textStyle: NwType.chip.copyWith(fontWeight: FontWeight.w700)),
        child: Text(favs.isEmpty ? 'Hinzufügen' : 'Bearbeiten'),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 2),
    );
    if (favs.isEmpty) {
      final suggestions = _suggestions(d);
      if (suggestions.isNotEmpty) {
        return [
          header,
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Vorschläge aus dem Verlauf', style: NwType.meta.copyWith(color: c.muted)),
          ),
          ..._tileRows(context, suggestions, suggestion: true),
        ];
      }
      return [
        header,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: NwCard(
            radius: 18,
            onTap: _nav.openFavorites,
            child: Row(
              children: [
                Icon(Icons.star_outline_rounded, color: c.faint),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Noch keine Favoriten. In Kontakte einen Eintrag antippen → „Favorit“.',
                    style: NwType.meta.copyWith(color: c.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return [header, ..._tileRows(context, favs)];
  }

  /// Most called numbers as contacts (directory name, else the name the call carried).
  List<Contact> _suggestions(Directory? d) {
    final all = <Contact>[...?d?.extensions, ...?d?.phonebook, ...?_phoneContacts.contacts];
    final doors = {for (final e in all) if (e.isDoorStation) e.number};
    final self = d?.self?.number;
    final numbers = suggestFavorites(_calls.calls, exclude: {...doors, if (self != null) self});
    return [
      for (final n in numbers)
        all.where((e) => e.number == n).firstOrNull ??
            Contact(
              number: n,
              name: _calls.calls.firstWhere((c) => c.number == n).name,
              isExtension: false,
            ),
    ];
  }

  List<Widget> _tileRows(BuildContext context, List<Contact> favs, {bool suggestion = false}) {
    final rows = <Widget>[];
    for (var i = 0; i < favs.length; i += 2) {
      rows.add(Padding(
        padding: EdgeInsets.fromLTRB(16, i == 0 ? 0 : 10, 16, 0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _favoriteTile(context, favs[i], suggestion: suggestion)),
              const SizedBox(width: 10),
              Expanded(
                  child: i + 1 < favs.length
                      ? _favoriteTile(context, favs[i + 1], suggestion: suggestion)
                      : const SizedBox.shrink()),
            ],
          ),
        ),
      ));
    }
    return rows;
  }

  Widget _favoriteTile(BuildContext context, Contact contact, {bool suggestion = false}) {
    final c = context.nw;
    final live = contact.isExtension ? (_pres.statusFor(contact.number) ?? ExtensionStatus(presence: contact.presence)) : null;
    final kind = avatarPresenceFor(live);
    final sub = contact.isDoorStation
        ? 'Türstation · ${contact.number}'
        : contact.isExtension
            ? 'Nebenstelle ${contact.number}'
            : contact.label.isNotEmpty
                ? 'Handy · ${contact.label}'
                : 'Telefonbuch';
    final state = live == null ? contact.number : live.label;
    final stateColor = kind == null || kind == AvatarPresence.offline ? c.faint : kind.color(c);
    void call() => CallLauncher.call(context, contact.number);
    void details() => ContactDetailsSheet.show(
          context,
          contact,
          onCall: call,
          presence: _pres,
        );
    return Semantics(
      button: true,
      label: '${contact.displayName} anrufen, $sub, $state',
      onTap: call,
      onLongPress: details,
      onLongPressHint: 'Details',
      excludeSemantics: true,
      child: NwCard(
        key: ValueKey('${suggestion ? 'suggest' : 'fav'}-${contact.number}'),
        radius: 20,
        onTap: call,
        onLongPress: details,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                contact.isDoorStation
                    ? const PresenceAvatar.door(size: 44)
                    : PresenceAvatar(name: contact.name, number: contact.number, presence: kind, size: 44),
                const Spacer(),
                if (suggestion)
                  NwIconButton(
                    key: ValueKey('suggest-star-${contact.number}'),
                    icon: Icons.star_outline_rounded,
                    label: '${contact.displayName} als Favorit',
                    onPressed: () => FavoritesStore.instance.toggle(contact.number),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(contact.displayName,
                style: NwType.rowTitle.copyWith(color: c.text, fontWeight: FontWeight.w800),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(sub, style: NwType.meta.copyWith(color: c.faint, fontSize: 12), maxLines: 2),
            const Spacer(),
            const SizedBox(height: 10),
            Text(state, style: NwType.meta.copyWith(color: stateColor, fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _voicemailCard(BuildContext context) {
    final c = context.nw;
    final unheard = _vm.messages.where(_vm.isUnheard).toList();
    if (unheard.isEmpty) return const SizedBox.shrink();
    final VoicemailMessage m = unheard.first;
    final name = m.callerName.isNotEmpty ? m.callerName : _dir.nameFor(m.callerNumber);
    final who = name.isNotEmpty ? name : (m.callerNumber.isNotEmpty ? m.callerNumber : 'Unbekannt');
    final title = unheard.length == 1 ? 'Neue Sprachnachricht · $who' : '${unheard.length} neue Sprachnachrichten · $who';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Semantics(
        button: true,
        label: '$title, im Verlauf anhören',
        onTap: () => _nav.openHistory(TimelineFilter.voicemail),
        excludeSemantics: true,
        child: NwCard(
          key: const Key('start-voicemail'),
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: () => _nav.openHistory(TimelineFilter.voicemail),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.blue, shape: BoxShape.circle),
                child: Icon(Icons.play_arrow_rounded, color: c.blueInk, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: NwType.rowTitle.copyWith(color: c.text, fontSize: 13.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      '${formatVoicemailTime(m.receivedAt, DateTime.now())} · ${formatCallDuration(m.duration)}',
                      style: NwType.meta.copyWith(color: c.faint, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.faint),
            ],
          ),
        ),
      ),
    );
  }
}
