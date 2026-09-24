import 'package:ha_phone_test/models/contact.dart';
import 'package:ha_phone_test/services/phone_contacts_source.dart';

/// In-memory address book; never touches the contacts/permission plugins.
class FakePhoneContactsSource implements PhoneContactsSource {
  FakePhoneContactsSource({
    this.access = PhoneContactsAccess.notAsked,
    this.grantOnRequest = true,
    this.contacts = const [],
  });

  PhoneContactsAccess access;
  bool grantOnRequest;
  List<Contact> contacts;
  int loadCount = 0;
  int requestCount = 0;
  int settingsOpened = 0;

  @override
  Future<PhoneContactsAccess> checkAccess() async => access;

  @override
  Future<PhoneContactsAccess> requestAccess() async {
    requestCount++;
    access = grantOnRequest ? PhoneContactsAccess.granted : PhoneContactsAccess.denied;
    return access;
  }

  @override
  Future<List<Contact>> loadContacts() async {
    loadCount++;
    return contacts;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

Contact phoneContact(String name, String number, [String label = 'Mobil']) =>
    Contact(number: number, name: name, isExtension: false, label: label);
