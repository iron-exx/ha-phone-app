import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/contact.dart';
import 'package:ha_phone_test/utils/contact_filter.dart';

const _contacts = [
  Contact(number: '11', name: 'sandro'),
  Contact(number: '12', name: 'Larissa'),
  Contact(number: '16', name: 'türklingel'),
  Contact(number: '0301234567', name: 'Pizzeria Roma', isExtension: false),
];

void main() {
  group('filterContacts', () {
    test('returns everything for an empty query', () {
      expect(filterContacts(_contacts, '  '), _contacts);
    });
    test('matches names case-insensitively', () {
      expect(filterContacts(_contacts, 'LAR').single.number, '12');
      expect(filterContacts(_contacts, 'Tür').single.number, '16');
    });
    test('matches numbers ignoring spaces and dashes', () {
      expect(filterContacts(_contacts, '0301 234').single.name, 'Pizzeria Roma');
      expect(filterContacts(_contacts, '030-123').single.name, 'Pizzeria Roma');
      expect(filterContacts(_contacts, '1').length, 4);
    });
    test('returns empty when nothing matches', () {
      expect(filterContacts(_contacts, 'xyz'), isEmpty);
    });
  });

  test('sortContacts sorts by name case-insensitively', () {
    expect(sortContacts(_contacts).map((c) => c.number), ['12', '0301234567', '11', '16']);
  });

  group('initialsFor', () {
    test('uses two words or the first two letters', () {
      expect(initialsFor('Pizzeria Roma', ''), 'PR');
      expect(initialsFor('sandro', '11'), 'SA');
      expect(initialsFor('türklingel', '16'), 'TÜ');
      expect(initialsFor('X', '1'), 'X');
    });
    test('falls back to digits of the number', () {
      expect(initialsFor('', '0174 1814689'), '01');
      expect(initialsFor('', ''), '?');
    });
  });
}
