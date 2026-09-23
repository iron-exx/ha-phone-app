import 'package:flutter/foundation.dart';

import 'local_store.dart';

/// Favourite numbers, stored locally only (the PBX has no favourites).
class FavoritesStore extends ChangeNotifier {
  FavoritesStore._();
  static final FavoritesStore instance = FavoritesStore._();

  Set<String> _numbers = {};
  bool _loaded = false;

  Set<String> get numbers => Set.unmodifiable(_numbers);

  bool isFavorite(String number) => _numbers.contains(number);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await loadPrefs();
    _numbers = {...?prefs?.getStringList(StoreKeys.favorites)};
    notifyListeners();
  }

  Future<void> toggle(String number) async {
    final next = {..._numbers};
    if (!next.remove(number)) next.add(number);
    _numbers = next;
    notifyListeners();
    final prefs = await loadPrefs();
    await prefs?.setStringList(StoreKeys.favorites, next.toList()..sort());
  }
}
