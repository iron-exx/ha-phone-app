import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/call_launcher.dart';
import '../services/directory_repository.dart';
import '../services/favorites_store.dart';
import '../services/phone_contacts_repository.dart';
import '../services/phone_contacts_source.dart';
import '../services/presence_repository.dart';
import '../utils/contact_filter.dart';
import '../widgets/contact_details_sheet.dart';
import '../widgets/contact_tile.dart';
import '../widgets/status_message.dart';

enum ContactSegment { extensions, phonebook, phone, favorites }

/// Kontakte tab: PBX extensions (with presence), PBX phonebook, the phone's
/// own address book (optional, asks for permission), local favourites. A
/// search looks through all sources at once, grouped by source.
class ContactsTab extends StatefulWidget {
  const ContactsTab({
    super.key,
    DirectoryRepository? repository,
    PresenceRepository? presence,
    PhoneContactsRepository? phoneContacts,
  })  : _repository = repository,
        _presence = presence,
        _phoneContacts = phoneContacts;

  final DirectoryRepository? _repository;

  /// The phone's address book; read lazily on the first Handy visit or search.
  final PhoneContactsRepository? _phoneContacts;

  /// Live presence/line state merged over the directory by number.
  final PresenceRepository? _presence;

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  final _search = TextEditingController();
  ContactSegment _segment = ContactSegment.extensions;
  late final AppLifecycleListener _lifecycle;

  DirectoryRepository get _repo => widget._repository ?? DirectoryRepository.instance;
  PresenceRepository get _presence => widget._presence ?? PresenceRepository.instance;
  PhoneContactsRepository get _phone => widget._phoneContacts ?? PhoneContactsRepository.instance;

  @override
  void initState() {
    super.initState();
    // Back from the system settings: the permission may have changed.
    _lifecycle = AppLifecycleListener(onResume: () {
      if (_phone.access != PhoneContactsAccess.granted && _phone.access != PhoneContactsAccess.unknown) {
        _phone.recheck();
      }
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _repo.refresh(),
      _presence.refresh(),
      if (_segment == ContactSegment.phone || _search.text.trim().isNotEmpty) _phone.refresh(),
    ]);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _search.dispose();
    super.dispose();
  }

  void _selectSegment(ContactSegment segment) {
    setState(() => _segment = segment);
    if (segment == ContactSegment.phone || segment == ContactSegment.favorites) _phone.ensureLoaded();
  }

  void _onSearchChanged(String query) {
    setState(() {});
    if (query.trim().isNotEmpty) _phone.ensureLoaded();
  }

  List<Contact> _source() {
    final d = _repo.directory;
    if (d == null) return const [];
    return switch (_segment) {
      // Own extension is shown in the Ich tab, not as a callable contact.
      ContactSegment.extensions =>
        sortContacts(d.extensions.where((c) => c.number != d.self?.number).toList()),
      ContactSegment.phonebook => sortContacts(d.phonebook),
      ContactSegment.phone => _phone.contacts ?? const [],
      ContactSegment.favorites => sortContacts([
          ...d.extensions,
          ...d.phonebook,
          ...?_phone.contacts,
        ].where((c) => FavoritesStore.instance.isFavorite(c.number)).toList()),
    };
  }

  void _call(Contact c) => CallLauncher.call(context, c.number);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kontakte')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Suchen nach Name oder Nummer',
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
          _SegmentChips(selected: _segment, onSelected: _selectSegment),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([_repo, _presence, _phone, FavoritesStore.instance]),
              builder: (context, _) => _buildList(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final error = _repo.error;
    final hasData = _repo.directory != null;
    final searching = _search.text.trim().isNotEmpty;
    if (!searching && _segment == ContactSegment.phone) return _buildPhoneSegment(context);
    if (!hasData && _repo.isLoading && !searching) {
      return const Center(child: CircularProgressIndicator());
    }
    final banner = error == null
        ? null
        : ErrorBanner(
            message: error.message,
            actionLabel: error.needsRepairing ? 'Neu koppeln' : 'Erneut',
            onAction: error.needsRepairing
                ? () async {
                    await Navigator.of(context).pushNamed('/qr-scan');
                    await _repo.refresh();
                  }
                : _repo.refresh,
          );
    if (searching) return _buildSearchResults(context, banner);
    final contacts = filterContacts(_source(), _search.text);
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: contacts.isEmpty ? 2 : contacts.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return banner ?? const SizedBox.shrink();
          if (contacts.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 48),
              child: StatusMessage(icon: _emptyIcon(), message: _emptyText(hasData)),
            );
          }
          return _tile(context, contacts[i - 1]);
        },
      ),
    );
  }

  Widget _tile(BuildContext context, Contact c) => ContactTile(
        contact: c,
        isFavorite: FavoritesStore.instance.isFavorite(c.number),
        status: c.isExtension ? _presence.statusFor(c.number) : null,
        onTap: () => _call(c),
        onLongPress: () => ContactDetailsSheet.show(context, c, onCall: () => _call(c), presence: _presence),
      );

  /// Hits from every source, each under a small header.
  Widget _buildSearchResults(BuildContext context, Widget? banner) {
    final d = _repo.directory;
    final sections = searchAllSources(
      query: _search.text,
      extensions: d?.extensions.where((c) => c.number != d.self?.number).toList() ?? const [],
      phonebook: d?.phonebook ?? const [],
      phone: _phone.contacts ?? const [],
    );
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (banner != null) banner,
          if (sections.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: StatusMessage(icon: Icons.search_off, message: _emptyText(d != null)),
            ),
          for (final s in sections) ...[
            _SectionHeader(title: s.title, count: s.contacts.length),
            for (final c in s.contacts) _tile(context, c),
          ],
        ],
      ),
    );
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
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: list.isEmpty ? 1 : list.length,
        itemBuilder: (context, i) {
          if (list.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 48),
              child: StatusMessage(
                icon: Icons.contacts_outlined,
                message: _phone.loadFailed
                    ? 'Adressbuch konnte nicht gelesen werden.\nZum Wiederholen nach unten ziehen.'
                    : 'Keine Kontakte mit Telefonnummer auf dem Handy.',
              ),
            );
          }
          return _tile(context, list[i]);
        },
      ),
    );
  }

  IconData _emptyIcon() => _segment == ContactSegment.favorites ? Icons.star_border : Icons.people_outline;


  String _emptyText(bool hasData) {
    if (_search.text.trim().isNotEmpty) return 'Keine Treffer für „${_search.text.trim()}“';
    if (!hasData) return 'Noch keine Kontakte geladen.\nZum Aktualisieren nach unten ziehen.';
    return switch (_segment) {
      ContactSegment.extensions => 'Keine Nebenstellen in der Anlage.',
      ContactSegment.phonebook => 'Das Telefonbuch der Anlage ist leer.',
      ContactSegment.phone => 'Keine Kontakte mit Telefonnummer auf dem Handy.',
      ContactSegment.favorites => 'Noch keine Favoriten.\nKontakt lange drücken → „Favorit“.',
    };
  }
}

/// Source picker. Compact chips scroll sideways: on 360 dp the first three
/// fit fully, Favoriten peeks in at the edge.
class _SegmentChips extends StatelessWidget {
  const _SegmentChips({required this.selected, required this.onSelected});

  final ContactSegment selected;
  final ValueChanged<ContactSegment> onSelected;

  static const _labels = {
    ContactSegment.extensions: 'Intern',
    ContactSegment.phonebook: 'Telefonbuch',
    ContactSegment.phone: 'Handy',
    ContactSegment.favorites: 'Favoriten',
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (final e in _labels.entries) ...[
            if (e.key != ContactSegment.extensions) const SizedBox(width: 8),
            ChoiceChip(
              label: Text(e.value),
              selected: selected == e.key,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onSelected(e.key),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small group header in the search results ("Handy · 3").
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        '$title · $count',
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
      ),
    );
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
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Icon(icon, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 24),
        Center(child: FilledButton(onPressed: onAction, child: Text(actionLabel))),
      ],
    );
  }
}
