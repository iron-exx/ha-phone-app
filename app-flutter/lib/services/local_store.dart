import 'package:shared_preferences/shared_preferences.dart';

/// Keys of everything the Dart side keeps in SharedPreferences. SIP
/// credentials and the device token are NOT here -- they live natively in
/// EncryptedSharedPreferences.
abstract final class StoreKeys {
  static const directoryCache = 'directory_cache_v1';
  static const favorites = 'favorites_v1';
  static const callsLastSeenMs = 'calls_last_seen_ms';
  static const voicemailHeard = 'voicemail_heard_v1';
  static const callsHiddenPbx = 'calls_hidden_pbx_v1';
}

/// Lazily resolved SharedPreferences. If the plugin fails (shouldn't happen
/// on Android) callers fall back to in-memory state.
Future<SharedPreferences?> loadPrefs() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (_) {
    return null;
  }
}
