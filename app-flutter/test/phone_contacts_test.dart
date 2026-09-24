import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/models/contact.dart';
import 'package:ha_phone_test/models/directory.dart';
import 'package:ha_phone_test/services/api_client.dart';
import 'package:ha_phone_test/services/directory_repository.dart';
import 'package:ha_phone_test/services/phone_contacts_repository.dart';
import 'package:ha_phone_test/services/phone_contacts_source.dart';
import 'package:ha_phone_test/utils/contact_filter.dart';
import 'package:ha_phone_test/utils/phone_number.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_api.dart';
import 'helpers/fake_phone_contacts.dart';

void main() {
  group('normalizePhoneNumber', () {
    test('strips spaces, dashes, slashes, dots and brackets', () {
      expect(normalizePhoneNumber(' 0301 / 23-45.67 '), '0301234567');
      expect(normalizePhoneNumber('(030) 1234567'), '0301234567');
    });
    test('+49 and 0049 become the national 0', () {
      expect(normalizePhoneNumber('+49 171 1234567'), '01711234567');
      expect(normalizePhoneNumber('0049 (171) 1234567'), '01711234567');
    });
    test('other international prefixes become 00, internal numbers stay', () {
      expect(normalizePhoneNumber('+43 1 234'), '00431234');
      expect(normalizePhoneNumber('11'), '11');
      expect(normalizePhoneNumber('*1'), '*1');
    });
    test('phoneNumbersMatch treats +49 and 0 as equal, never matches empty', () {
      expect(phoneNumbersMatch('+49 30 1234567', '030-1234567'), isTrue);
      expect(phoneNumbersMatch('0301234567', '0301234568'), isFalse);
      expect(phoneNumbersMatch('', ''), isFalse);
    });
  });

  group('searchAllSources', () {
    const ext = [Contact(number: '11', name: 'Sandra Büro')];
    const book = [Contact(number: '0301234567', name: 'Sanitär Meier', isExtension: false)];
    final phone = [phoneContact('Sandra Privat', '+49 171 555'), phoneContact('Zahnarzt', '0301234999', 'Arbeit')];

    test('groups hits by source in fixed order', () {
      final sections = searchAllSources(query: 'san', extensions: ext, phonebook: book, phone: phone);
      expect(sections.map((s) => s.title), ['Nebenstellen', 'Telefonbuch', 'Handy']);
      expect(sections.last.contacts.single.name, 'Sandra Privat');
    });
    test('drops empty groups and matches numbers across +49/0', () {
      final sections = searchAllSources(query: '0171', extensions: ext, phonebook: book, phone: phone);
      expect(sections.single.title, 'Handy');
      final byPrefix = searchAllSources(query: '030 1234', extensions: ext, phonebook: book, phone: phone);
      expect(byPrefix.map((s) => s.title), ['Telefonbuch', 'Handy']);
    });
    test('empty query returns nothing', () {
      expect(searchAllSources(query: ' ', extensions: ext), isEmpty);
    });
  });

  group('PhoneContactsRepository', () {
    test('does not load or resolve names without permission', () async {
      final src = FakePhoneContactsSource(contacts: [phoneContact('Mama', '0171 555')]);
      final repo = PhoneContactsRepository(source: src);
      await repo.ensureLoaded();
      expect(repo.access, PhoneContactsAccess.notAsked);
      expect(src.loadCount, 0);
      expect(repo.nameFor('0171555'), '');
    });
    test('loads once when granted and resolves normalized numbers', () async {
      final src = FakePhoneContactsSource(
        access: PhoneContactsAccess.granted,
        contacts: [phoneContact('Mama', '+49 171 555-0'), phoneContact('Zoe', '030 12')],
      );
      final repo = PhoneContactsRepository(source: src);
      await Future.wait([repo.ensureLoaded(), repo.ensureLoaded()]);
      await repo.ensureLoaded();
      expect(src.loadCount, 1);
      expect(repo.contacts!.map((c) => c.name), ['Mama', 'Zoe']);
      expect(repo.nameFor('01715550'), 'Mama');
      expect(repo.nameFor('0049 171 5550'), 'Mama');
      expect(repo.nameFor('999'), '');
    });
    test('request: granted loads, denied does not', () async {
      final ok = FakePhoneContactsSource(contacts: [phoneContact('A', '1')]);
      final r1 = PhoneContactsRepository(source: ok);
      await r1.requestAccess();
      expect(r1.access, PhoneContactsAccess.granted);
      expect(r1.contacts, hasLength(1));

      final no = FakePhoneContactsSource(grantOnRequest: false);
      final r2 = PhoneContactsRepository(source: no);
      await r2.requestAccess();
      expect(r2.access, PhoneContactsAccess.denied);
      expect(no.loadCount, 0);
    });
    test('revoked permission forgets the contacts on recheck', () async {
      final src = FakePhoneContactsSource(access: PhoneContactsAccess.granted, contacts: [phoneContact('A', '0301')]);
      final repo = PhoneContactsRepository(source: src);
      await repo.ensureLoaded();
      src.access = PhoneContactsAccess.denied;
      await repo.recheck();
      expect(repo.contacts, isNull);
      expect(repo.nameFor('0301'), '');
    });
  });

  group('DirectoryRepository.nameFor', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('PBX names win, phone contacts fill the gaps', () async {
      final src = FakePhoneContactsSource(
        access: PhoneContactsAccess.granted,
        contacts: [phoneContact('Mama', '+49 171 555'), phoneContact('Handy-Pizza', '0301234567')],
      );
      final phone = PhoneContactsRepository(source: src);
      final pbx = FakePbx({
        'GET /api/mobile/directory': (_) => jsonResponse({
              'self': {'number': '13', 'name': 'Ich'},
              'extensions': [
                {'number': '11', 'name': 'sandro'},
              ],
              'phonebook': [
                {'number': '030 1234567', 'name': 'Pizzeria'},
              ],
            }),
      });
      final dir = DirectoryRepository(api: pbx.api, authLoader: testAuthLoader, phoneContacts: phone);
      var notified = 0;
      dir.addListener(() => notified++);
      await dir.init();
      await phone.ensureLoaded();

      expect(dir.nameFor('11'), 'sandro');
      expect(dir.nameFor('+49301234567'), 'Pizzeria');
      expect(dir.nameFor('0171555'), 'Mama');
      expect(dir.nameFor('0999'), '');
      expect(notified, greaterThan(0));
    });

    test('without phone contacts only the directory is used', () {
      const d = Directory(phonebook: [Contact(number: '0301234567', name: 'Pizzeria', isExtension: false)]);
      expect(d.nameFor('+49 30 1234567'), 'Pizzeria');
      expect(DirectoryRepository(api: ApiClient(), authLoader: testAuthLoader).nameFor('0171555'), '');
    });
  });
}
