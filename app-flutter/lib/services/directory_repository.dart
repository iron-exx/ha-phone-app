import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/directory.dart';
import 'api_client.dart';
import 'local_store.dart';
import 'phone_contacts_repository.dart';
import 'sip_channel.dart';

/// Holds the PBX directory (extensions, phonebook, own extension), backed by
/// a local cache so contacts show instantly and offline. With
/// [phoneContacts], [nameFor] falls back to the phone's address book.
class DirectoryRepository extends ChangeNotifier {
  DirectoryRepository({
    ApiClient? api,
    Future<DeviceAuth> Function()? authLoader,
    PhoneContactsRepository? phoneContacts,
  })  : _api = api ?? ApiClient(),
        _authLoader = authLoader ?? loadAuthFromNative,
        _phoneContacts = phoneContacts {
    // Names resolved from the address book change when it loads.
    phoneContacts?.addListener(notifyListeners);
  }

  static final DirectoryRepository instance = DirectoryRepository(phoneContacts: PhoneContactsRepository.instance);

  final ApiClient _api;
  final Future<DeviceAuth> Function() _authLoader;
  final PhoneContactsRepository? _phoneContacts;

  Directory? _directory;
  ApiException? _error;
  bool _loading = false;
  bool _cacheLoaded = false;

  /// Last successfully loaded directory (fresh or cached), null if never loaded.
  Directory? get directory => _directory;

  /// Error of the last refresh; cleared on success.
  ApiException? get error => _error;
  bool get isLoading => _loading;

  /// Device credentials from the native store (shared by all repositories).
  static Future<DeviceAuth> loadAuthFromNative() async =>
      DeviceAuth.fromMap(await SipChannel.instance.getDeviceAuth());

  /// Loads the cache (once) and then fetches a fresh copy.
  /// Also reads the phone's address book if already permitted (no prompt).
  Future<void> init() async {
    final phone = _phoneContacts;
    if (phone != null) unawaited(phone.ensureLoaded());
    await _loadCache();
    await refresh();
  }

  Future<void> _loadCache() async {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    final prefs = await loadPrefs();
    final raw = prefs?.getString(StoreKeys.directoryCache);
    if (raw == null || _directory != null) return;
    try {
      _directory = Directory.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      notifyListeners();
    } catch (e) {
      debugPrint('directory cache unreadable, ignoring: $e');
    }
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final auth = await _authLoader();
      final fresh = await _api.fetchDirectory(auth);
      _directory = fresh;
      _error = null;
      await _saveCache(fresh);
      await _pushDoorCodes(fresh);
    } on ApiException catch (e) {
      _error = e;
    } catch (e) {
      debugPrint('directory refresh failed: $e');
      _error = const ApiException(ApiErrorKind.unreachable);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _saveCache(Directory d) async {
    final prefs = await loadPrefs();
    await prefs?.setString(StoreKeys.directoryCache, jsonEncode(d.toJson()));
  }

  /// Native side needs the codes to answer "Tür öffnen" (also from the
  /// ringing screen, where Dart isn't involved).
  Future<void> _pushDoorCodes(Directory d) async {
    try {
      await SipChannel.instance.setDoorCodes(d.doorCodes);
      await SipChannel.instance.setDoorActions(d.doorActions);
      await SipChannel.instance.setDoorOpenRemote(d.doorOpenRemoteNumbers);
    } catch (e) {
      debugPrint('setDoorCodes/setDoorActions/setDoorOpenRemote failed: $e');
    }
  }

  /// Name for a number from the directory, else from the phone's address
  /// book (if permitted), '' if unknown.
  String nameFor(String number) {
    final fromPbx = _directory?.nameFor(number) ?? '';
    if (fromPbx.isNotEmpty) return fromPbx;
    return _phoneContacts?.nameFor(number) ?? '';
  }

  @override
  void dispose() {
    _phoneContacts?.removeListener(notifyListeners);
    super.dispose();
  }

  /// Forget everything (device unpaired).
  Future<void> clear() async {
    _directory = null;
    _error = null;
    final prefs = await loadPrefs();
    await prefs?.remove(StoreKeys.directoryCache);
    notifyListeners();
  }
}
