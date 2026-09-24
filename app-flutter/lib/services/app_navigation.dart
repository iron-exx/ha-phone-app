import 'package:flutter/foundation.dart';

import '../utils/timeline.dart';

/// Tabs of the shell, in bottom-bar order (Wählen is the raised centre button).
enum AppTab { start, history, dial, contacts, me }

/// Cross-tab navigation: the Start cards, deep links and notifications ask
/// the shell to show a tab, e.g. "Verlauf with the Voicemail filter".
class AppNavigation extends ChangeNotifier {
  AppNavigation();

  static final AppNavigation instance = AppNavigation();

  AppTab _tab = AppTab.start;
  TimelineFilter? _pendingHistoryFilter;
  int _contactSearchRequests = 0;
  bool _contactFavoritesRequested = false;

  AppTab get tab => _tab;

  /// Increments whenever the Kontakte search field should get the focus.
  int get contactSearchRequests => _contactSearchRequests;

  void select(AppTab tab) {
    if (_tab == tab) return;
    _tab = tab;
    notifyListeners();
  }

  /// Verlauf with [filter] preselected (consumed once by the tab).
  void openHistory([TimelineFilter filter = TimelineFilter.all]) {
    _pendingHistoryFilter = filter;
    _tab = AppTab.history;
    notifyListeners();
  }

  /// Returns and clears the filter requested by [openHistory].
  TimelineFilter? takeHistoryFilter() {
    final f = _pendingHistoryFilter;
    _pendingHistoryFilter = null;
    return f;
  }

  /// Kontakte with the search field focused.
  void openContactSearch() {
    _contactSearchRequests++;
    _tab = AppTab.contacts;
    notifyListeners();
  }

  /// Kontakte with the Favoriten source selected.
  void openFavorites() {
    _contactFavoritesRequested = true;
    _tab = AppTab.contacts;
    notifyListeners();
  }

  /// Returns and clears a pending [openFavorites] request.
  bool takeFavoritesRequest() {
    final r = _contactFavoritesRequested;
    _contactFavoritesRequested = false;
    return r;
  }

  /// Native route from a notification/deep link; true if handled here.
  bool handleRoute(String route) {
    switch (route) {
      case 'voicemail':
        openHistory(TimelineFilter.voicemail);
        return true;
      case 'history' || 'missed_calls':
        openHistory(route == 'missed_calls' ? TimelineFilter.missed : TimelineFilter.all);
        return true;
    }
    return false;
  }
}
