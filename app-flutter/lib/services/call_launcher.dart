import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'call_events.dart';
import 'sip_channel.dart';

/// Single place that starts an outgoing call from any tab: checks the
/// microphone permission, clears a stale disconnect event, dials and opens
/// the active-call screen.
/// Mailbox access number (*97 = own mailbox without PIN, HA-Phone 0.7.104).
const kVoicemailNumber = '*97';

abstract final class CallLauncher {
  /// Replaceable in tests (permission_handler has no test implementation).
  static Future<bool> Function() requestMicrophone =
      () async => (await Permission.microphone.request()).isGranted;

  static Future<void> call(BuildContext context, String number) async {
    final target = number.trim();
    if (target.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (!await requestMicrophone()) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Mikrofon-Berechtigung wird zum Telefonieren benötigt.'),
      ));
      return;
    }
    CallEvents.instance.lastDisconnected = null;
    try {
      await SipChannel.instance.makeCall(target);
    } catch (e) {
      debugPrint('makeCall failed: $e');
      messenger.showSnackBar(const SnackBar(
        content: Text('Anruf fehlgeschlagen – Verbindung zur Anlage prüfen.'),
      ));
      return;
    }
    await navigator.pushNamed('/active-call');
  }
}
