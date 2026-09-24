import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/app_navigation.dart';
import '../services/call_launcher.dart';
import '../services/directory_repository.dart';
import '../services/door_opener.dart';
import '../services/favorites_store.dart';
import '../services/phone_contacts_repository.dart';
import '../services/phone_contacts_source.dart';
import '../services/presence_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/contact_filter.dart';
import '../widgets/contact_details_sheet.dart';
import '../widgets/contact_tile.dart';
import '../widgets/door_open_button.dart';
import '../widgets/nw_widgets.dart';
import '../widgets/presence_avatar.dart';
import '../widgets/status_message.dart';

enum ContactSegment {
  all('Alle'),
  extensions('Nebenstellen'),
  phone('Handy'),
  phonebook('Telefonbuch'),
  favorites('Favoriten');

  const ContactSegment(this.label);
  final String label;
}

/// Kontakte: search over all sources, source chips Alle · Nebenstellen ·
/// Handy · Telefonbuch · Favoriten, sections Türstationen (open via webhook or call the door) ·
/// Kolleg:innen (live presence) · Handy · Telefonbuch. Row tap opens the
/// details sheet (Favorit), the green button calls.
class ContactsTab extends StatefulWidget {
  const ContactsTab({
    super.key,
    DirectoryRepository? repository,
    PresenceRepository? presence,
    PhoneContactsRepository? phoneContacts,
    AppNavigation? navigation,
    this.doorOpener,
  })  : _repository = repository,
        _presence = presence,
        _phoneContacts = phoneContacts,
        _navigation = navigation;

  final DirectoryRepository? _repository;

  /// The phone's address book; read lazily on the first Handy visit or search.
  final PhoneContactsRepository? _phoneContacts;

  /// Live presence/line state merged over the directory by number.
  final PresenceRepository? _presence;
  final AppNavigation? _navigation;

  /// Door webhook seam for tests (default: [DoorOpener.instance]).
  final DoorOpener? doorOpener;

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  ContactSegment _segment = ContactSegment.all;
  late final AppLifecycleListener _lifecycle;
  late int _searchRequests;

  DirectoryRepository get _repo => widget._repository ?? DirectoryRepository.instance;
  PresenceRepository get _presence => widget._presence ?? PresenceRepository.instance;
  PhoneContactsRepository get _phone => widget._phoneContacts ?? PhoneContactsRepository.instance;
  AppNavigation get _nav => widget._navigation ?? AppNavigation.instance;

  @override
  void initState() {
    super.initState();
    _searchRequests = _nav.contactSearchRequests;
    _nav.addListener(_onNavigation);
    // Back from the system settings: the permission may have changed.
    _lifecycle = AppLifecycleListener(onResume: () {
      if (_phone.access != PhoneContactsAccess.granted && _phone.access != PhoneContactsAccess.unknown) {
        _phone.recheck();
      }
    });
  }

  @override
  void dispose() {
    _nav.removeListener(_onNavigation);
    _lifecycle.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onNavigation() {
    if (_nav.takeFavoritesRequest()) _selectSegment(ContactSegment.favorites);
    if (_nav.contactSearchRequests != _searchRequests) {
      _searchRequests = _nav.contactSearchRequests;
      // After the shell has made this tab visible (focus needs it on stage).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _repo.refresh(),
      _presence.refresh(),
      if (_phone.access == PhoneContactsAccess.granted) _phone.refresh(),
    ]);
  }

  void _selectSegment(ContactSegment segment) {
    setState(() => _segment = segment);
    _phone.ensureLoaded();
  }

  void _onSearchChanged(String query) {
    setState(() {});
    if (query.trim().isNotEmpty) _phone.ensureLoaded();
  }

  void _call(Contact c) => CallLauncher.call(context, c.number);

  List<Contact> get _extensions {
    final d = _repo.directory;
    if (d == null) return const [];
    // Own extension is shown on Start/Ich, not as a callable contact.
    return sortContacts(d.extensions.where((c) => c.number != d.self?.number).toList());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const PageHeader('Kontakte'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                onChanged: _onSearchChanged,
                style: NwType.rowTitle.copyWith(color: c.text, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'Name, Nummer oder Nebenstelle',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Suche leeren',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(_search.clear),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: NwChipRow(children: [
                for (final s in ContactSegment.values)
                  NwChip(
                    key: ValueKey('segment-${s.name}'),
                    label: s.label,
                    selected: _segment == s,
                    onTap: () => _selectSegment(s),
                  ),
              ]),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([_repo, _presence, _phone, FavoritesStore.instance]),
                builder: (context, _) => _buildList(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _banner(BuildContext context) {
    final error = _repo.error;
    if (error == null) return null;
    return ErrorBanner(
      message: error.message,
      actionLabel: error.needsRepairing ? 'Neu koppeln' : 'Erneut',
      onAction: error.needsRepairing
          ? () async {
              await Navigator.of(context).pushNamed('/qr-scan');
              await _repo.refresh();
            }
          : _repo.refresh,
    );
  }

  Widget _buildList(BuildContext context) {
    final searching = _search.text.trim().isNotEmpty;
    if (!searching && _segment == ContactSegment.phone) return _buildPhoneSegment(context);
    final hasData = _repo.directory != null;
    if (!hasData && _repo.isLoading && !searching) {
      return const Center(child: CircularProgressIndicator());
    }
    final banner = _banner(context);
    final children = <Widget>[
      if (banner != null) banner,
      ...(searching ? _searchResults(context) : _segmentSections(context)),
    ];
    if (children.length == (banner == null ? 0 : 1)) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 48),
        child: StatusMessage(icon: _emptyIcon(), message: _emptyText(hasData)),
      ));
    }
    children.add(const SizedBox(height: 24));
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: children),
    );
  }

  List<Widget> _section(String title, List<Contact> contacts) => contacts.isEmpty
      ? const []
      : [
          SectionHeader(title),
          for (final c in contacts) c.isDoorStation ? _doorRow(context, c) : _tile(context, c),
        ];

  List<Widget> _segmentSections(BuildContext context) {
    final d = _repo.directory;
    final ext = _extensions;
    final doors = ext.where((c) => c.isDoorStation).toList();
    final colleagues = ext.where((c) => !c.isDoorStation).toList();
    final phonebook = sortContacts(d?.phonebook ?? const []);
    final phone = _phone.access == PhoneContactsAccess.granted ? (_phone.contacts ?? const <Contact>[]) : const <Contact>[];
    switch (_segment) {
      case ContactSegment.all:
        return [
          ..._section('Türstationen', doors),
          ..._section('Kolleg:innen', colleagues),
          ..._section('Handy', phone),
          ..._section('Telefonbuch', phonebook),
        ];
      case ContactSegment.extensions:
        return [..._section('Türstationen', doors), ..._section('Kolleg:innen', colleagues)];
      case ContactSegment.phonebook:
        return _section('Telefonbuch', phonebook);
      case ContactSegment.favorites:
        final favs = resolveFavorites(
          FavoritesStore.instance.numbers,
          extensions: ext,
          phonebook: phonebook,
          phone: _phone.contacts ?? const [],
        );
        return _section('Favoriten', favs);
      case ContactSegment.phone:
        return _section('Handy', phone);
    }
  }

  Widget _tile(BuildContext context, Contact c) => ContactTile(
        contact: c,
        isFavorite: FavoritesStore.instance.isFavorite(c.number),
        status: c.isExtension ? _presence.statusFor(c.number) : null,
        onTap: () => _details(c),
        onLongPress: () => _details(c),
        onCall: () => _call(c),
      );

  void _details(Contact c) => ContactDetailsSheet.show(context, c, onCall: () => _call(c), presence: _presence);

  /// Door station row: amber door symbol, "türklingel · 16 · Video", Öffnen/Anrufen.
  Widget _doorRow(BuildContext context, Contact door) {
    final c = context.nw;
    final meta = [door.number, if (door.video) 'Video'].join(' · ');
    return InkWell(
      key: ValueKey('door-${door.number}'),
      onTap: () => _details(door),
      onLongPress: () => _details(door),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              const PresenceAvatar.door(size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(door.displayName, style: NwType.rowTitle.copyWith(color: c.text), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text('Türstation · $meta', style: NwType.meta.copyWith(color: c.faint)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DoorOpenButton(door: door, compact: true, opener: widget.doorOpener, onCall: () => _call(door)),
            ],
          ),
        ),
      ),
    );
  }

  /// Hits from every source, each under a small header.
  List<Widget> _searchResults(BuildContext context) {
    final d = _repo.directory;
    final sections = searchAllSources(
      query: _search.text,
      extensions: _extensions,
      phonebook: d?.phonebook ?? const [],
      phone: _phone.contacts ?? const [],
    );
    return [
      for (final s in sections) ..._section('${s.title} · ${s.contacts.length}', s.contacts),
    ];
  }

  /// Handy segment: permission explanation / denied hint / address book.
  Widget _buildPhoneSegment(BuildContext context) {
    final access = _phone.access;
    if (access == PhoneContactsAccess.unknown) {
      // First visit through a path that did not trigger the check yet.
      WidgetsBinding.instance.addPostFrameCallback((_) => _phone.ensureLoaded());
      return const Center(child: CircularProgressIndicator());
    }
    if (access == PhoneContactsAccess.notAsked) {
      return _PermissionPrompt(
        key: const Key('phone-contacts-explain'),
        icon: Icons.contacts_outlined,
        title: 'Handy-Adressbuch einbinden',
        message: 'HA-Phone kann die Kontakte auf diesem Handy anzeigen, damit Sie sie direkt '
            'über die Anlage anrufen können und Anrufer mit Namen erscheinen.\n'
            'Die Kontakte bleiben auf dem Gerät und werden nicht an die Anlage übertragen.',
        actionLabel: 'Zugriff erlauben',
        onAction: _phone.requestAccess,
      );
    }
    if (access == PhoneContactsAccess.denied) {
      return _PermissionPrompt(
        key: const Key('phone-contacts-denied'),
        icon: Icons.block,
        title: 'Kein Zugriff auf die Kontakte',
        message: 'Der Zugriff auf das Adressbuch wurde abgelehnt. Sie können ihn in den '
            'App-Einstellungen unter „Berechtigungen → Kontakte“ erlauben.',
        actionLabel: 'Einstellungen öffnen',
        onAction: _phone.openSettings,
      );
    }
    final contacts = _phone.contacts;
    if (contacts == null && _phone.isLoading) return const Center(child: CircularProgressIndicator());
    final list = contacts ?? const <Contact>[];
    return RefreshIndicator(
      onRefresh: _phone.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: StatusMessage(
                icon: Icons.contacts_outlined,
                message: _phone.loadFailed
                    ? 'Adressbuch konnte nicht gelesen werden.\nZum Wiederholen nach unten ziehen.'
                    : 'Keine Kontakte mit Telefonnummer auf dem Handy.',
              ),
            )
          else
            ..._section('Handy', list),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  IconData _emptyIcon() => _segment == ContactSegment.favorites ? Icons.star_border : Icons.people_outline;

  String _emptyText(bool hasData) {
    if (_search.text.trim().isNotEmpty) return 'Keine Treffer für „${_search.text.trim()}“';
    if (!hasData) return 'Noch keine Kontakte geladen.\nZum Aktualisieren nach unten ziehen.';
    return switch (_segment) {
      ContactSegment.all || ContactSegment.extensions => 'Keine Nebenstellen in der Anlage.',
      ContactSegment.phonebook => 'Das Telefonbuch der Anlage ist leer.',
      ContactSegment.phone => 'Keine Kontakte mit Telefonnummer auf dem Handy.',
      ContactSegment.favorites => 'Noch keine Favoriten.\nKontakt antippen → „Favorit“.',
    };
  }
}

/// Centered explanation with one action (permission prompt / settings hint).
class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        Icon(icon, size: 52, color: c.blue),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: NwType.display(22).copyWith(color: c.text)),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: NwType.meta.copyWith(color: c.muted, fontSize: 14)),
        const SizedBox(height: 24),
        Center(child: FilledButton(onPressed: onAction, child: Text(actionLabel))),
      ],
    );
  }
}
