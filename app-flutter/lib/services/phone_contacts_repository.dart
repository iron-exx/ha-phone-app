import 'package:flutter/foundation.dart';

import '../models/contact.dart';
import '../utils/contact_filter.dart';
import '../utils/phone_number.dart';
import 'phone_contacts_source.dart';

/// The phone's own address book, optional: only read once the user allowed
/// it. Loaded lazily, kept in memory only (never cached to disk).
class PhoneContactsRepository extends ChangeNotifier {
  PhoneContactsRepository({PhoneContactsSource? source}) : _source = source ?? const DevicePhoneContactsSource();

  static final PhoneContactsRepository instance = PhoneContactsRepository();

  final PhoneContactsSource _source;

  PhoneContactsAccess _access = PhoneContactsAccess.unknown;
  List<Contact>? _contacts;
  Map<String, String> _names = const {};
  bool _loading = false;
  bool _loadFailed = false;
  Future<void>? _pending;

  PhoneContactsAccess get access => _access;

  /// Sorted, one entry per number; null until loaded (or not permitted).
  List<Contact>? get contacts => _contacts;
  bool get isLoading => _loading;

  /// The last load threw (access was granted, reading failed).
  bool get loadFailed => _loadFailed;

  /// Checks the permission (no prompt) and loads once if granted.
  /// Concurrent callers share one run.
  Future<void> ensureLoaded() {
    if (_access != PhoneContactsAccess.unknown && (_access != PhoneContactsAccess.granted || _contacts != null)) {
      return Future.value();
    }
    return _pending ??= _checkAndLoad().whenComplete(() => _pending = null);
  }

  /// Re-reads the permission, e.g. back from the system settings.
  Future<void> recheck() => _pending ??= _checkAndLoad().whenComplete(() => _pending = null);

  Future<void> _checkAndLoad() async {
    final PhoneContactsAccess access;
    try {
      access = await _source.checkAccess();
    } catch (e) {
      debugPrint('contacts permission check failed: $e');
      _setAccess(PhoneContactsAccess.denied);
      return;
    }
    _setAccess(access);
    if (access == PhoneContactsAccess.granted && _contacts == null) await _load();
  }

  /// Asks the user (system dialog) and loads on success.
  Future<void> requestAccess() async {
    PhoneContactsAccess access;
    try {
      access = await _source.requestAccess();
    } catch (e) {
      debugPrint('contacts permission request failed: $e');
      access = PhoneContactsAccess.denied;
    }
    _setAccess(access);
    if (access == PhoneContactsAccess.granted) await _load();
  }

  /// Pull-to-refresh: re-reads the address book if permitted.
  Future<void> refresh() async {
    if (_access != PhoneContactsAccess.granted) return recheck();
    await _load();
  }

  Future<void> openSettings() async {
    try {
      await _source.openSettings();
    } catch (e) {
      debugPrint('openAppSettings failed: $e');
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final loaded = sortContacts(await _source.loadContacts());
      _contacts = loaded;
      _names = _nameIndex(loaded);
      _loadFailed = false;
    } catch (e) {
      debugPrint('reading phone contacts failed: $e');
      _loadFailed = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _setAccess(PhoneContactsAccess access) {
    final revoked = access != PhoneContactsAccess.granted && _contacts != null;
    if (access == _access && !revoked) return;
    _access = access;
    if (revoked) {
      _contacts = null;
      _names = const {};
    }
    notifyListeners();
  }

  static Map<String, String> _nameIndex(List<Contact> contacts) => {
        for (final c in contacts)
          if (c.name.isNotEmpty && normalizePhoneNumber(c.number).isNotEmpty) normalizePhoneNumber(c.number): c.name,
      };

  /// Name for a number (formatting and +49/0 ignored), '' if unknown or
  /// not permitted.
  String nameFor(String number) {
    if (_access != PhoneContactsAccess.granted) return '';
    return _names[normalizePhoneNumber(number)] ?? '';
  }
}
