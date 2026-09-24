import '../models/contact.dart';
import 'phone_number.dart';

/// Case-insensitive search on name, or on number ignoring spaces/dashes so
/// "0301 234" still finds "0301234567" (and "0171" finds "+49 171 ...").
List<Contact> filterContacts(List<Contact> contacts, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return contacts;
  final digits = q.replaceAll(RegExp(r'[\s\-/()]'), '');
  final normalized = normalizePhoneNumber(q);
  return contacts.where((c) {
    if (c.name.toLowerCase().contains(q)) return true;
    if (digits.isEmpty) return false;
    return c.number.replaceAll(RegExp(r'[\s\-/()]'), '').contains(digits) ||
        (normalized.isNotEmpty && normalizePhoneNumber(c.number).contains(normalized));
  }).toList();
}

/// One group of search results with its small header.
class ContactSection {
  const ContactSection(this.title, this.contacts);

  final String title;
  final List<Contact> contacts;
}

/// A search over every source at once: Nebenstellen, Telefonbuch (PBX),
/// Handy (phone address book), each sorted; empty groups are left out.
List<ContactSection> searchAllSources({
  required String query,
  List<Contact> extensions = const [],
  List<Contact> phonebook = const [],
  List<Contact> phone = const [],
}) {
  if (query.trim().isEmpty) return const [];
  return [
    for (final (title, source) in [('Nebenstellen', extensions), ('Telefonbuch', phonebook), ('Handy', phone)])
      if (filterContacts(source, query) case final hits when hits.isNotEmpty) ContactSection(title, sortContacts(hits)),
  ];
}

/// Sorts by display name (case-insensitive), numbers as tie-breaker.
List<Contact> sortContacts(List<Contact> contacts) {
  final sorted = [...contacts];
  sorted.sort((a, b) {
    final byName = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    return byName != 0 ? byName : a.number.compareTo(b.number);
  });
  return sorted;
}

/// Avatar initials: first letters of the first two words, or the first two
/// characters of a single word; first two digits for unnamed numbers.
String initialsFor(String name, String number) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.length >= 2) {
    return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
  }
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  final n = number.replaceAll(RegExp(r'\D'), '');
  if (n.isEmpty) return '?';
  return n.length >= 2 ? n.substring(0, 2) : n;
}
