import '../models/extension_status.dart';

/// Dialled to take over the call the own extension has on another device,
/// e.g. the desk phone, which then hangs up (HA-Phone 0.7.114).
const kCallFlipCode = '*55';

/// After this app's own call ends the PBX may still report the line busy
/// until it has processed the hang-up; presence snapshots fetched within
/// this window after the call are not trusted.
const kCallFlipGrace = Duration(seconds: 3);

/// Whether to offer "Hierher holen": the PBX reports the own line busy and
/// that is not this app's own call. The app's call makes the line busy too,
/// so it is hidden while the app has a call and until a presence snapshot
/// from after that call's end arrives.
bool shouldOfferCallFlip({
  required LineState? ownLine,
  required bool hasOwnCall,
  required DateTime? snapshotAt,
  DateTime? ownCallEndedAt,
}) {
  if (hasOwnCall || ownLine != LineState.busy || snapshotAt == null) return false;
  return ownCallEndedAt == null || snapshotAt.isAfter(ownCallEndedAt.add(kCallFlipGrace));
}
