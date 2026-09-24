import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/reachability.dart';

/// Reads the native reachability snapshot and opens the matching system
/// settings pages (see ReachabilityMonitor.kt / ReachSettings.kt).
class ReachabilityService {
  ReachabilityService({MethodChannel? channel}) : _channel = channel ?? _defaultChannel;

  static final ReachabilityService instance = ReachabilityService();

  static const _defaultChannel = MethodChannel('de.haphone.app.test/sip_calls');

  final MethodChannel _channel;

  /// null if the native side could not answer (e.g. not available on this platform).
  Future<ReachabilitySnapshot?> load() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('getReachability');
      return raw == null ? null : ReachabilitySnapshot.fromMap(raw);
    } on PlatformException catch (e) {
      debugPrint('getReachability failed: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// True if a settings page was opened (falls back to the app details page natively).
  Future<bool> openSettings(ReachabilitySettingsPage page) async {
    try {
      return await _channel.invokeMethod<bool>('openReachabilitySettings', page.name) ?? false;
    } on PlatformException catch (e) {
      debugPrint('openReachabilitySettings(${page.name}) failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
