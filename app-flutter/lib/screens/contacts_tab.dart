import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/call_launcher.dart';
import '../services/directory_repository.dart';
import '../services/favorites_store.dart';
import '../services/presence_repository.dart';
import '../utils/contact_filter.dart';
import '../widgets/contact_details_sheet.dart';
import '../widgets/contact_tile.dart';
import '../widgets/status_message.dart';

enum ContactSegment { extensions, phonebook, favorites }

/// Kontakte tab: PBX extensions (with presence), PBX phonebook, local favourites.
class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key, DirectoryRepository? repository, PresenceRepository? presence})
      : _repository = repository,
        _presence = presence;

  final DirectoryRepository? _repository;

  /// Live presence/line state merged over the directory by number.
  final PresenceRepository? _presence;

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  final _search = TextEditingController();
  ContactSegment _segment = ContactSegment.extensions;

  DirectoryRepository get _repo => widget._repository ?? DirectoryRepository.instance;
  PresenceRepository get _presence => widget._presence ?? PresenceRepository.instance;

  Future<void> _refreshAll() async {
    await Future.wait([_repo.refresh(), _presence.refresh()]);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Contact> _source() {
    final d = _repo.directory;
    if (d == null) return const [];
    return switch (_segment) {
      // Own extension is shown in the Ich tab, not as a callable contact.
      ContactSegment.extensions =>
        sortContacts(d.extensions.where((c) => c.number != d.self?.number).toList()),
      ContactSegment.phonebook => sortContacts(d.phonebook),
      ContactSegment.favorites => sortContacts([
          ...d.extensions,
          ...d.phonebook,
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
              onChanged: (_) => setState(() {}),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ContactSegment>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ContactSegment.extensions, label: Text('Nebenstellen')),
                  ButtonSegment(value: ContactSegment.phonebook, label: Text('Telefonbuch')),
                  ButtonSegment(value: ContactSegment.favorites, label: Text('Favoriten')),
                ],
                selected: {_segment},
                onSelectionChanged: (s) => setState(() => _segment = s.first),
              ),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([_repo, _presence, FavoritesStore.instance]),
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
    if (!hasData && _repo.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final contacts = filterContacts(_source(), _search.text);
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
          final c = contacts[i - 1];
          return ContactTile(
            contact: c,
            isFavorite: FavoritesStore.instance.isFavorite(c.number),
            status: c.isExtension ? _presence.statusFor(c.number) : null,
            onTap: () => _call(c),
            onLongPress: () => ContactDetailsSheet.show(context, c, onCall: () => _call(c)),
          );
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
      ContactSegment.favorites => 'Noch keine Favoriten.\nKontakt lange drücken → „Favorit“.',
    };
  }
}
