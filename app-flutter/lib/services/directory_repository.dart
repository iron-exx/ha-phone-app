import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/directory.dart';
import 'api_client.dart';
import 'local_store.dart';
import 'sip_channel.dart';

/// Holds the PBX directory (extensions, phonebook, own extension), backed by
/// a local cache so contacts show instantly and offline.
class DirectoryRepository extends ChangeNotifier {
  DirectoryRepository({ApiClient? api, Future<DeviceAuth> Function()? authLoader})
      : _api = api ?? ApiClient(),
        _authLoader = authLoader ?? loadAuthFromNative;

  static final DirectoryRepository instance = DirectoryRepository();

  final ApiClient _api;
  final Future<DeviceAuth> Function() _authLoader;

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
  Future<void> init() async {
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
    } catch (e) {
      debugPrint('setDoorCodes/setDoorActions failed: $e');
    }
  }

  /// Name for a number from the directory, '' if unknown.
  String nameFor(String number) => _directory?.nameFor(number) ?? '';

  /// Forget everything (device unpaired).
  Future<void> clear() async {
    _directory = null;
    _error = null;
    final prefs = await loadPrefs();
    await prefs?.remove(StoreKeys.directoryCache);
    notifyListeners();
  }
}
