import 'package:flutter/foundation.dart';

import '../models/pbx_call.dart';
import '../utils/call_merge.dart';
import 'api_client.dart';
import 'directory_repository.dart';
import 'foreground_poller.dart';
import 'local_store.dart';
import 'sip_channel.dart';

/// Call history of the Verlauf tab: the local history (recorded natively)
/// merged with the PBX log (GET /api/mobile/calls, all devices of the own
/// extension), plus the "missed since last opened" badge count.
///
/// PBX entries can't be deleted on the PBX; deleting them here hides their
/// id locally (shared_preferences).
class CallHistoryStore extends ChangeNotifier {
  CallHistoryStore({
    ApiClient? api,
    Future<DeviceAuth> Function()? authLoader,
    Duration pollInterval = const Duration(seconds: 60),
  })  : _api = api ?? ApiClient(),
        _authLoader = authLoader ?? DirectoryRepository.loadAuthFromNative {
    _poller = ForegroundPoller(interval: pollInterval, onTick: refreshPbx);
  }

  static final CallHistoryStore instance = CallHistoryStore();

  final ApiClient _api;
  final Future<DeviceAuth> Function() _authLoader;
  late final ForegroundPoller _poller;

  List<CallHistoryEntry> _entries = const [];
  List<PbxCall> _pbx = const [];
  List<MergedCall> _calls = const [];
  Set<String> _hidden = {};
  bool _hiddenLoaded = false;
  DateTime? _lastSeen;
  bool _lastSeenLoaded = false;
  bool _visible = false;
  bool _pbxLoading = false;
  String? _error;
  ApiException? _pbxError;

  /// Local entries only, newest first.
  List<CallHistoryEntry> get entries => _entries;

  /// Merged rows (local + PBX), newest first.
  List<MergedCall> get calls => _calls;
  String? get error => _error;

  /// Error of the last PBX fetch (null on success); the list still shows
  /// the local entries.
  ApiException? get pbxError => _pbxError;
  int get unseenMissed => countMergedMissedSince(_calls, _lastSeen);

  /// When the Verlauf was last looked at (missed calls after it are new), null if never.
  DateTime? get lastSeen => _lastSeen;

  /// True while the Anrufe tab is on screen: polls the PBX every minute
  /// and counts new missed calls as seen.
  void setVisible(bool visible) {
    _visible = visible;
    _poller.active = visible;
  }

  Future<void> refreshAll() => Future.wait([load(), refreshPbx()]);

  /// Reloads the local history.
  Future<void> load() async {
    await _loadLastSeen();
    await _loadHidden();
    try {
      _entries = await SipChannel.instance.getCallHistory();
      _error = null;
    } catch (e) {
      debugPrint('getCallHistory failed: $e');
      _error = 'Anrufliste konnte nicht geladen werden.';
    }
    await _changed();
  }

  /// Fetches the PBX log; errors keep the last known PBX entries.
  Future<void> refreshPbx() async {
    if (_pbxLoading) return;
    _pbxLoading = true;
    try {
      await _loadHidden();
      _pbx = await _api.fetchCalls(await _authLoader());
      _pbxError = null;
      await _pruneHidden();
    } on ApiException catch (e) {
      _pbxError = e;
    } catch (e) {
      debugPrint('calls refresh failed: $e');
      _pbxError = const ApiException(ApiErrorKind.unreachable);
    } finally {
      _pbxLoading = false;
    }
    await _changed();
  }

  Future<void> _changed() async {
    _calls = mergeCallHistory(_entries, _pbx, hiddenPbxIds: _hidden);
    notifyListeners();
    if (_visible) await markSeen();
  }

  Future<void> _loadLastSeen() async {
    if (_lastSeenLoaded) return;
    _lastSeenLoaded = true;
    final ms = (await loadPrefs())?.getInt(StoreKeys.callsLastSeenMs);
    if (ms != null) _lastSeen = DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _loadHidden() async {
    if (_hiddenLoaded) return;
    _hiddenLoaded = true;
    _hidden = {...?(await loadPrefs())?.getStringList(StoreKeys.callsHiddenPbx)};
  }

  /// Keeps the stored set small: only ids the PBX still reports.
  Future<void> _pruneHidden() async {
    final present = _pbx.map((c) => c.id).toSet();
    final pruned = _hidden.intersection(present);
    if (pruned.length == _hidden.length) return;
    _hidden = pruned;
    await _saveHidden();
  }

  Future<void> _saveHidden() async {
    await (await loadPrefs())?.setStringList(StoreKeys.callsHiddenPbx, _hidden.toList()..sort());
  }

  /// Called while the Anrufe tab is visible: clears the badge.
  Future<void> markSeen() async {
    final now = DateTime.now();
    _lastSeen = now;
    _lastSeenLoaded = true;
    notifyListeners();
    await (await loadPrefs())?.setInt(StoreKeys.callsLastSeenMs, now.millisecondsSinceEpoch);
  }

  /// Deletes the local part natively and hides the PBX part. The list
  /// updates synchronously (Dismissible needs the row gone right away).
  Future<void> deleteCall(MergedCall call) async {
    final pbx = call.pbx;
    final local = call.local;
    if (pbx != null) _hidden = {..._hidden, pbx.id};
    if (local != null) _entries = _entries.where((e) => e.id != local.id).toList();
    await _changed();
    if (pbx != null) await _saveHidden();
    if (local != null) await _deleteNative(local.id);
  }

  /// Deletes a local entry.
  Future<void> delete(String id) async {
    _entries = _entries.where((e) => e.id != id).toList();
    await _changed();
    await _deleteNative(id);
  }

  Future<void> _deleteNative(String id) async {
    try {
      await SipChannel.instance.deleteCallHistoryEntry(id);
    } catch (e) {
      debugPrint('deleteCallHistoryEntry failed: $e');
      await load();
    }
  }

  /// "Verlauf löschen": clears the local history and hides all PBX entries.
  Future<void> clear() async {
    _hidden = {..._hidden, ..._pbx.map((c) => c.id)};
    _entries = const [];
    await _changed();
    await _saveHidden();
    try {
      await SipChannel.instance.clearCallHistory();
    } catch (e) {
      debugPrint('clearCallHistory failed: $e');
      await load();
    }
  }

  /// Forget the PBX part (device unpaired); the local history stays.
  Future<void> clearPbx() async {
    _pbx = const [];
    _pbxError = null;
    _hidden = {};
    await (await loadPrefs())?.remove(StoreKeys.callsHiddenPbx);
    await _changed();
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }
}
