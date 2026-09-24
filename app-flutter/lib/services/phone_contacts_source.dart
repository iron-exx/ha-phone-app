import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:permission_handler/permission_handler.dart';

import '../models/contact.dart';

/// Whether the app may read the phone's address book.
enum PhoneContactsAccess {
  /// Not checked yet.
  unknown,

  /// Never asked (or asked and dismissed, Android may ask again).
  notAsked,

  /// Refused; only the system settings can change it.
  denied,

  granted,
}

/// Access to the phone's own address book. Replaced by a fake in tests
/// (the plugins have no test implementation).
abstract interface class PhoneContactsSource {
  /// Current state without prompting the user.
  Future<PhoneContactsAccess> checkAccess();

  /// Shows the system permission dialog.
  Future<PhoneContactsAccess> requestAccess();

  /// One entry per phone number (isExtension false, [Contact.label] set).
  Future<List<Contact>> loadContacts();

  Future<void> openSettings();
}

/// Real address book via permission_handler + flutter_contacts.
class DevicePhoneContactsSource implements PhoneContactsSource {
  const DevicePhoneContactsSource();

  @override
  Future<PhoneContactsAccess> checkAccess() async {
    final s = await Permission.contacts.status;
    if (s.isGranted || s.isLimited) return PhoneContactsAccess.granted;
    if (s.isPermanentlyDenied || s.isRestricted) return PhoneContactsAccess.denied;
    return PhoneContactsAccess.notAsked;
  }

  @override
  Future<PhoneContactsAccess> requestAccess() async {
    final s = await Permission.contacts.request();
    return (s.isGranted || s.isLimited) ? PhoneContactsAccess.granted : PhoneContactsAccess.denied;
  }

  @override
  Future<List<Contact>> loadContacts() async {
    final raw = await fc.FlutterContacts.getContacts(withProperties: true);
    return [
      for (final c in raw)
        for (final p in c.phones)
          if (p.number.trim().isNotEmpty)
            Contact(
              number: p.number.trim(),
              name: c.displayName,
              isExtension: false,
              label: phoneLabelText(p.label, p.customLabel),
            ),
    ];
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}

/// German label for the kind of number ("Mobil", "Privat", "Arbeit").
String phoneLabelText(fc.PhoneLabel label, String customLabel) => switch (label) {
      fc.PhoneLabel.mobile || fc.PhoneLabel.iPhone => 'Mobil',
      fc.PhoneLabel.home => 'Privat',
      fc.PhoneLabel.work || fc.PhoneLabel.companyMain => 'Arbeit',
      fc.PhoneLabel.workMobile => 'Arbeit mobil',
      fc.PhoneLabel.main => 'Hauptnummer',
      fc.PhoneLabel.faxHome || fc.PhoneLabel.faxWork || fc.PhoneLabel.faxOther => 'Fax',
      fc.PhoneLabel.pager || fc.PhoneLabel.workPager => 'Pager',
      fc.PhoneLabel.car => 'Auto',
      fc.PhoneLabel.custom => customLabel.trim(),
      fc.PhoneLabel.other => 'Sonstige',
      _ => '',
    };
