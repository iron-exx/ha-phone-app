import 'package:flutter/foundation.dart';

import '../models/doorbell_event.dart';
import '../utils/single_flight.dart';
import 'api_client.dart';
import 'directory_repository.dart';
import 'foreground_poller.dart';

/// Doorbell history (GET /api/mobile/doorbell): the start page shows the latest
/// picture, the history screen the list. Pictures are cached in memory.
class DoorbellRepository extends ChangeNotifier {
  DoorbellRepository({
    ApiClient? api,
    Future<DeviceAuth> Function()? authLoader,
    Duration pollInterval = const Duration(seconds: 60),
  })  : _api = api ?? ApiClient(),
        _authLoader = authLoader ?? DirectoryRepository.loadAuthFromNative {
    _poller = ForegroundPoller(interval: pollInterval, onTick: refresh);
  }

  static final DoorbellRepository instance = DoorbellRepository();
  static const _maxCachedImages = 40;

  final ApiClient _api;
  final Future<DeviceAuth> Function() _authLoader;
  late final ForegroundPoller _poller;
  final _flight = SingleFlight();
  final Map<int, Uint8List> _images = {};

  List<DoorbellEvent> _events = const [];
  bool _unsupported = false;
  int _epoch = 0;

  List<DoorbellEvent> get events => _events;
  bool get isUnsupported => _unsupported;

  /// Newest ring of [door] (or of any door).
  DoorbellEvent? latestFor(String? door) {
    for (final e in _events) {
      if (door == null || e.doorNumber == door) return e;
    }
    return null;
  }

  void setPolling(bool enabled) => _poller.active = enabled;

  Future<void> refresh() => _flight.run(() async {
        final epoch = _epoch;
        try {
          final auth = await _authLoader();
          if (!auth.isComplete) return;
          final list = await _api.fetchDoorbell(auth, limit: 50);
          if (epoch != _epoch) return;
          _events = list;
          _unsupported = false;
          notifyListeners();
        } on ApiException catch (e) {
          if (e.kind == ApiErrorKind.unsupported && epoch == _epoch) {
            _unsupported = true;
            notifyListeners();
          }
        } catch (e) {
          debugPrint('doorbell refresh failed: $e');
        }
      });

  /// Picture of [event] (null without picture or when the download fails).
  Future<Uint8List?> image(DoorbellEvent event) async {
    if (!event.hasImage) return null;
    final cached = _images[event.id];
    if (cached != null) return cached;
    try {
      final bytes = Uint8List.fromList(await _api.downloadDoorbellImage(await _authLoader(), event.id));
      if (_images.length >= _maxCachedImages) _images.remove(_images.keys.first);
      _images[event.id] = bytes;
      return bytes;
    } catch (e) {
      debugPrint('doorbell image ${event.id} failed: $e');
      return null;
    }
  }

  /// Unpairing / other box: forget everything.
  void clear() {
    _epoch++;
    _events = const [];
    _images.clear();
    _unsupported = false;
    notifyListeners();
  }
}
