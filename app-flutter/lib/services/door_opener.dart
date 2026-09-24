import 'dart:async';

import 'package:flutter/services.dart';

import 'api_client.dart';
import 'directory_repository.dart';

/// Outcome of [DoorOpener.open].
enum DoorOpenResult {
  /// The PBX called the door's webhook.
  opened,

  /// 404: no webhook configured for this door (fall back to calling / DTMF).
  noWebhook,
}

/// Opens a door station through its webhook on the PBX
/// (POST /api/mobile/door-open, HA-Phone 0.7.117). Works without a call,
/// for doors whose directory entry has `door_open_remote`.
class DoorOpener {
  DoorOpener({ApiClient? api, Future<DeviceAuth> Function()? authLoader})
      : _api = api ?? ApiClient(),
        _authLoader = authLoader ?? DirectoryRepository.loadAuthFromNative;

  static final DoorOpener instance = DoorOpener();

  final ApiClient _api;
  final Future<DeviceAuth> Function() _authLoader;

  /// Throws [ApiException] (German message) on network/auth/server errors.
  Future<DoorOpenResult> open(String extension) async {
    final opened = await _api.openDoorRemote(await _authLoader(), extension);
    return opened ? DoorOpenResult.opened : DoorOpenResult.noWebhook;
  }
}

/// How long the green "Tür geöffnet ✓" state stays.
const kDoorOpenedFeedback = Duration(seconds: 2);

/// Double pulse after the door opened (Nachtwache: "doppelter Impuls").
void doorOpenedHaptic() {
  HapticFeedback.heavyImpact();
  unawaited(Future<void>.delayed(const Duration(milliseconds: 120), HapticFeedback.heavyImpact));
}
