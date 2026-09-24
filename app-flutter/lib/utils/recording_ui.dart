import '../models/recording.dart';
import '../services/api_client.dart';
import '../services/sip_channel.dart';

/// Recording-state key of a call line (number + answer time).
String lineKeyOf(CurrentCall line) => recordingLineKey(line.number, line.connectedAt);

/// Keys of all lines of the current call (on screen + held/waiting).
Set<String> lineKeysOf(CurrentCall? call) => {
      if (call != null) lineKeyOf(call),
      if (call?.other != null) lineKeyOf(call!.other!),
    };

/// SnackBar text for a failed start/stop of a call recording.
String recordingErrorText(ApiException e, {required bool starting}) {
  if (e.kind == ApiErrorKind.notAllowed) return 'Gesprächsaufzeichnung ist für Ihre Nebenstelle nicht freigegeben.';
  if (e.kind == ApiErrorKind.unreachable) {
    return 'Anlage nicht erreichbar – Aufnahme nicht ${starting ? 'gestartet' : 'gestoppt'}.';
  }
  if (e.kind == ApiErrorKind.server && e.statusCode == 409) {
    return starting
        ? 'Aufnahme nicht gestartet – Gespräch auf der Anlage nicht eindeutig gefunden.'
        : 'Keine laufende Aufnahme gefunden.';
  }
  if (e.kind == ApiErrorKind.server && e.statusCode == 502) {
    return 'Anlage konnte die Aufnahme nicht ${starting ? 'starten' : 'stoppen'}.';
  }
  return e.message;
}

/// "1 Aufnahme", "3 Aufnahmen", "Keine Aufnahmen".
String recordingCountText(int count) => switch (count) {
      0 => 'Keine Aufnahmen',
      1 => '1 Aufnahme',
      _ => '$count Aufnahmen',
    };
