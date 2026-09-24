import 'package:flutter/foundation.dart';

import '../models/voicemail.dart';
import 'api_client.dart';
import 'directory_repository.dart';
import 'foreground_poller.dart';
import 'local_store.dart';
import 'pbx_audio.dart';

/// Visual voicemail (GET /api/mobile/voicemail), refreshed every 60 s while
/// the app is in the foreground and whenever the Voicemail tab opens.
/// Messages played on this device count as heard locally (the PBX only moves
/// them to Old when played on a phone), so the badge clears right away.
class VoicemailRepository extends ChangeNotifier {
  VoicemailRepository({
    ApiClient? api,
    Future<DeviceAuth> Function()? authLoader,
    Duration pollInterval = const Duration(seconds: 60),
  })  : _api = api ?? ApiClient(),
        _authLoader = authLoader ?? DirectoryRepository.loadAuthFromNative {
    _poller = ForegroundPoller(interval: pollInterval, onTick: refresh);
  }

  static final VoicemailRepository instance = VoicemailRepository();

  final ApiClient _api;
  final Future<DeviceAuth> Function() _authLoader;
  late final ForegroundPoller _poller;

  List<VoicemailMessage> _messages = const [];
  Set<String> _heard = {};
  bool _heardLoaded = false;
  bool _loaded = false;
  bool _loading = false;
  ApiException? _error;

  /// Newest first.
  List<VoicemailMessage> get messages => _messages;
  ApiException? get error => _error;
  bool get isLoading => _loading;

  /// True once a refresh succeeded (distinguishes "empty" from "not loaded").
  bool get hasLoaded => _loaded;
  bool get isUnsupported => _error?.kind == ApiErrorKind.unsupported;

  /// Badge count on the Voicemail tab.
  int get unheardCount => countUnheard(_messages, _heard);

  /// New on the PBX and not yet played here.
  bool isUnheard(VoicemailMessage m) => m.isNew && !_heard.contains(m.heardKey);

  /// Stream/download source of a message for the player.
  Future<PbxAudioSource> audioSource(VoicemailMessage m) async {
    final auth = await _authLoader();
    return PbxAudioSource(
      uri: _api.voicemailAudioUri(auth, m),
      headers: ApiClient.authHeaders(auth),
      download: () => _api.downloadVoicemail(auth, m),
      tempFileName: 'voicemail_${m.path?.name ?? 'message'}_${m.heardKey.hashCode}.wav',
    );
  }

  /// Started by the shell for its lifetime (badge needs it on every tab).
  void setPolling(bool enabled) => _poller.active = enabled;

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      await _loadHeard();
      final box = await _api.fetchVoicemail(await _authLoader());
      _messages = box.messages;
      _loaded = true;
      _error = null;
      await _pruneHeard();
    } on ApiException catch (e) {
      _error = e;
    } catch (e) {
      debugPrint('voicemail refresh failed: $e');
      _error = const ApiException(ApiErrorKind.unreachable);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> markHeard(VoicemailMessage m) async {
    if (_heard.contains(m.heardKey)) return;
    _heard = {..._heard, m.heardKey};
    notifyListeners();
    await _saveHeard();
  }

  /// Deletes on the PBX first, then locally; rethrows [ApiException].
  Future<void> delete(VoicemailMessage m) async {
    await _api.deleteVoicemail(await _authLoader(), m);
    _messages = _messages.where((e) => e.id != m.id).toList();
    _heard = {..._heard}..remove(m.heardKey);
    notifyListeners();
    await _saveHeard();
  }

  Future<void> _loadHeard() async {
    if (_heardLoaded) return;
    _heardLoaded = true;
    final prefs = await loadPrefs();
    _heard = {...?prefs?.getStringList(StoreKeys.voicemailHeard)};
  }

  /// Keeps the stored set small: only keys of messages that still exist.
  Future<void> _pruneHeard() async {
    final present = _messages.map((m) => m.heardKey).toSet();
    final pruned = _heard.intersection(present);
    if (pruned.length == _heard.length) return;
    _heard = pruned;
    await _saveHeard();
  }

  Future<void> _saveHeard() async {
    final prefs = await loadPrefs();
    await prefs?.setStringList(StoreKeys.voicemailHeard, _heard.toList()..sort());
  }

  /// Forget everything (device unpaired).
  Future<void> clear() async {
    _messages = const [];
    _heard = {};
    _loaded = false;
    _error = null;
    notifyListeners();
    final prefs = await loadPrefs();
    await prefs?.remove(StoreKeys.voicemailHeard);
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }
}
