import 'package:flutter/foundation.dart';

/// Bumped whenever pairing or unpairing changes the stored credentials, so the
/// root screen re-checks them even when the change happened on a route it did
/// not push itself (e.g. a `haphone://provision` link opened from outside).
final ValueNotifier<int> provisioningRevision = ValueNotifier<int>(0);
