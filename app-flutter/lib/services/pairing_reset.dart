import 'package:flutter/foundation.dart';

import '../models/ring_settings.dart';
import 'call_history_store.dart';
import 'directory_repository.dart';
import 'favorites_store.dart';
import 'forwarding_repository.dart';
import 'presence_repository.dart';
import 'recordings_repository.dart';
import 'ring_settings_repository.dart';
import 'sip_channel.dart';
import 'voicemail_repository.dart';

/// Forgets everything that belongs to the current pairing, before unpairing
/// or after a new pairing (possibly with another box): all PBX-backed
/// repositories, favourites, the ring policy and the native copies (door
/// codes/actions/webhook doors, Android Auto directory and favourites).
/// The local call history stays. Every parameter defaults to the singleton.
Future<void> resetForPairing({
  DirectoryRepository? directory,
  PresenceRepository? presence,
  ForwardingRepository? forwarding,
  CallHistoryStore? history,
  VoicemailRepository? voicemail,
  RecordingsRepository? recordings,
  FavoritesStore? favorites,
  RingSettingsRepository? ring,
}) async {
  // In-flight refreshes see the bumped epoch/generation and drop their result.
  await (directory ?? DirectoryRepository.instance).clear();
  (presence ?? PresenceRepository.instance).clear();
  (forwarding ?? ForwardingRepository.instance).clear();
  await (history ?? CallHistoryStore.instance).clearPbx();
  await (voicemail ?? VoicemailRepository.instance).clear();
  (recordings ?? RecordingsRepository.instance).clear();
  await (favorites ?? FavoritesStore.instance).clear();
  try {
    await (ring ?? RingSettingsRepository.instance).update(const RingSettings());
  } catch (e) {
    debugPrint('resetting ring policy failed: $e');
  }
  final native = SipChannel.instance;
  try {
    await native.setDoorCodes(const {});
    await native.setDoorActions(const {});
    await native.setDoorOpenRemote(const []);
    await native.setCarDirectory(const [], '');
  } catch (e) {
    debugPrint('clearing native directory copies failed: $e');
  }
  try {
    await native.tailscaleReset();
  } catch (e) {
    debugPrint('tailscale reset failed: $e');
  }
}
