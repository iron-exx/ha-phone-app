import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException, PlatformException;

import '../models/preview_camera.dart';
import '../utils/single_flight.dart';
import 'api_client.dart';
import 'directory_repository.dart';
import 'local_store.dart';
import 'sip_channel.dart';

/// Extra preview cameras: the PBX says which Home Assistant cameras the admin
/// shared, this phone keeps which of them it shows (locally, like favourites).
/// [shown] feeds the start page, the call screen and (native copy) the ringing screen.
class PreviewCamerasRepository extends ChangeNotifier {
  PreviewCamerasRepository({
    ApiClient? api,
    Future<DeviceAuth> Function()? authLoader,
    Future<void> Function(List<Map<String, String>>)? pushToNative,
  })  : _api = api ?? ApiClient(),
        _authLoader = authLoader ?? DirectoryRepository.loadAuthFromNative,
        _pushToNative = pushToNative ?? SipChannel.instance.setPreviewCameras;

  static final PreviewCamerasRepository instance = PreviewCamerasRepository();

  final ApiClient _api;
  final Future<DeviceAuth> Function() _authLoader;
  final Future<void> Function(List<Map<String, String>>) _pushToNative;
  final _flight = SingleFlight();
  final Map<String, Uint8List> _last = {};

  List<PreviewCamera> _available = const [];
  Set<String> _selected = {};
  bool _selectionLoaded = false;
  bool _loaded = false;
  bool _unsupported = false;
  int _epoch = 0;

  /// Shared by the admin, in the admin's order.
  List<PreviewCamera> get available => _available;

  /// Shared and chosen on this phone.
  List<PreviewCamera> get shown => [
        for (final c in _available)
          if (_selected.contains(c.entityId)) c,
      ];

  bool isSelected(String entityId) => _selected.contains(entityId);

  /// Newest picture fetched so far (a new view shows it at once; cameras can take 25 s).
  Uint8List? lastPicture(String entityId) => _last[entityId];
  bool get hasLoaded => _loaded;

  /// PBX older than 0.7.141.
  bool get isUnsupported => _unsupported;

  Future<void> _loadSelection() async {
    if (_selectionLoaded) return;
    _selectionLoaded = true;
    final prefs = await loadPrefs();
    _selected = {...?prefs?.getStringList(StoreKeys.previewCameras)};
  }

  Future<void> refresh() => _flight.run(() async {
        final epoch = _epoch;
        await _loadSelection();
        try {
          final auth = await _authLoader();
          if (!auth.isComplete) return;
          final list = await _api.fetchCameras(auth);
          if (epoch != _epoch) return;
          _available = list;
          _loaded = true;
          _unsupported = false;
          notifyListeners();
          await _syncNative();
        } on ApiException catch (e) {
          if (e.kind == ApiErrorKind.unsupported && epoch == _epoch) {
            _unsupported = true;
            _loaded = true;
            notifyListeners();
          }
        } catch (e) {
          debugPrint('preview cameras refresh failed: $e');
        }
      });

  Future<void> toggle(String entityId) async {
    await _loadSelection();
    final next = {..._selected};
    if (!next.remove(entityId)) next.add(entityId);
    _selected = next;
    notifyListeners();
    final prefs = await loadPrefs();
    await prefs?.setStringList(StoreKeys.previewCameras, next.toList()..sort());
    await _syncNative();
  }

  /// Current picture of [camera]; null when the PBX or the camera gives none.
  Future<Uint8List?> snapshot(PreviewCamera camera) async {
    try {
      final bytes = Uint8List.fromList(await _api.downloadCameraSnapshot(await _authLoader(), camera.entityId));
      _last[camera.entityId] = bytes;
      return bytes;
    } catch (e) {
      debugPrint('camera snapshot ${camera.entityId} failed: $e');
      return null;
    }
  }

  Future<void> _syncNative() async {
    try {
      await _pushToNative([for (final c in shown) c.toJson()]);
    } on PlatformException catch (e) {
      debugPrint('setPreviewCameras failed: $e');
    } on MissingPluginException {
      // Widget tests: no native side.
    }
  }

  /// Unpairing / other box: forget the list and the choice.
  Future<void> clear() async {
    _epoch++;
    _available = const [];
    _last.clear();
    _selected = {};
    _selectionLoaded = true;
    _loaded = false;
    _unsupported = false;
    notifyListeners();
    final prefs = await loadPrefs();
    await prefs?.remove(StoreKeys.previewCameras);
    await _syncNative();
  }
}
