import 'package:flutter/foundation.dart';

import '../utils/missed_calls.dart';
import 'local_store.dart';
import 'sip_channel.dart';

/// Local call history (recorded natively) plus the "missed since last
/// opened" badge count for the Anrufe tab.
class CallHistoryStore extends ChangeNotifier {
  CallHistoryStore._();
  static final CallHistoryStore instance = CallHistoryStore._();

  List<CallHistoryEntry> _entries = const [];
  DateTime? _lastSeen;
  bool _lastSeenLoaded = false;
  String? _error;

  /// Newest first.
  List<CallHistoryEntry> get entries => _entries;
  String? get error => _error;
  int get unseenMissed => countMissedSince(_entries, _lastSeen);

  Future<void> load() async {
    await _loadLastSeen();
    try {
      _entries = await SipChannel.instance.getCallHistory();
      _error = null;
    } catch (e) {
      debugPrint('getCallHistory failed: $e');
      _error = 'Anrufliste konnte nicht geladen werden.';
    }
    notifyListeners();
  }

  Future<void> _loadLastSeen() async {
    if (_lastSeenLoaded) return;
    _lastSeenLoaded = true;
    final ms = (await loadPrefs())?.getInt(StoreKeys.callsLastSeenMs);
    if (ms != null) _lastSeen = DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Called while the Anrufe tab is visible: clears the badge.
  Future<void> markSeen() async {
    final now = DateTime.now();
    _lastSeen = now;
    _lastSeenLoaded = true;
    notifyListeners();
    await (await loadPrefs())?.setInt(StoreKeys.callsLastSeenMs, now.millisecondsSinceEpoch);
  }

  Future<void> delete(String id) async {
    _entries = _entries.where((e) => e.id != id).toList();
    notifyListeners();
    try {
      await SipChannel.instance.deleteCallHistoryEntry(id);
    } catch (e) {
      debugPrint('deleteCallHistoryEntry failed: $e');
      await load();
    }
  }

  Future<void> clear() async {
    _entries = const [];
    notifyListeners();
    try {
      await SipChannel.instance.clearCallHistory();
    } catch (e) {
      debugPrint('clearCallHistory failed: $e');
      await load();
    }
  }
}
