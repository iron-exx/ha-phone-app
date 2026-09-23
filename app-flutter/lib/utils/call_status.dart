import '../services/sip_channel.dart';
import 'formatters.dart';

/// Status line under the caller's name: "Verbinde…", "Klingelt…", or the
/// running duration since the call was answered.
String callStatusText(CurrentCall? call, DateTime now, {bool onHold = false}) {
  if (call == null) return 'Verbinde…';
  final connectedAt = call.connectedAt;
  if (connectedAt != null) {
    final timer = formatCallTimer(now.difference(connectedAt));
    return onHold ? '$timer · gehalten' : timer;
  }
  return call.state == 'ringing' ? 'Klingelt…' : 'Verbinde…';
}
