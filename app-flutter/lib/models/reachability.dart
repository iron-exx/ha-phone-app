// Reachability snapshot from the native side (`getReachability`), for the
// "Erreichbarkeit" screen: everything that decides whether the phone still
// rings after days without a call.

/// Vendor family (from Build.MANUFACTURER), for OEM-specific advice such as
/// Samsung "Nie in Standby versetzte Apps" or Xiaomi "Autostart".
enum OemFamily {
  samsung,
  xiaomi,
  huawei,
  oneplus,
  oppo,
  vivo,
  google,
  other;

  static OemFamily fromName(String? value) {
    for (final f in OemFamily.values) {
      if (f.name == value) return f;
    }
    return other;
  }
}

/// System settings pages `openReachabilitySettings` can open; [name] is the channel key.
enum ReachabilitySettingsPage {
  exactAlarm,
  batteryOptimization,
  fullScreenIntent,
  notifications,
  appDetails,
}

/// Something that can keep calls from ringing, in the order the screen should list them.
enum ReachabilityIssue {
  notificationsDisabled(ReachabilitySettingsPage.notifications),
  fullScreenIntentDenied(ReachabilitySettingsPage.fullScreenIntent),
  batteryOptimized(ReachabilitySettingsPage.batteryOptimization),
  exactAlarmsDenied(ReachabilitySettingsPage.exactAlarm),
  serviceStopped(null),
  notRegistered(null);

  const ReachabilityIssue(this.settingsPage);

  /// Where the user can fix it; null if the app has to fix it itself.
  final ReachabilitySettingsPage? settingsPage;
}

class ReachabilitySnapshot {
  const ReachabilitySnapshot({
    required this.notificationsEnabled,
    required this.canUseFullScreenIntent,
    required this.ignoringBatteryOptimizations,
    required this.canScheduleExactAlarms,
    required this.registered,
    required this.serviceRunning,
    this.registrationState = 'unknown',
    this.lastRegisteredAt,
    this.registrationExpiresAt,
    this.lastWakeupAt,
    this.lastTransportDropAt,
    this.nextAlarmAt,
    this.manufacturer = '',
    this.oemFamily = OemFamily.other,
    this.sdkInt = 0,
  });

  factory ReachabilitySnapshot.fromMap(Map<Object?, Object?> m) {
    bool flag(String key) => m[key] == true;
    DateTime? time(String key) {
      final v = m[key];
      return v is int && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    }

    return ReachabilitySnapshot(
      notificationsEnabled: flag('notificationsEnabled'),
      canUseFullScreenIntent: flag('canUseFullScreenIntent'),
      ignoringBatteryOptimizations: flag('ignoringBatteryOptimizations'),
      canScheduleExactAlarms: flag('canScheduleExactAlarms'),
      registered: flag('registered'),
      serviceRunning: flag('serviceRunning'),
      registrationState: m['registrationState'] as String? ?? 'unknown',
      lastRegisteredAt: time('lastRegisteredAt'),
      registrationExpiresAt: time('registrationExpiresAt'),
      lastWakeupAt: time('lastWakeupAt'),
      lastTransportDropAt: time('lastTransportDropAt'),
      nextAlarmAt: time('nextAlarmAt'),
      manufacturer: m['manufacturer'] as String? ?? '',
      oemFamily: OemFamily.fromName(m['oemFamily'] as String?),
      sdkInt: m['sdkInt'] as int? ?? 0,
    );
  }

  final bool notificationsEnabled;

  /// Always true below Android 14 (no separate permission there).
  final bool canUseFullScreenIntent;
  final bool ignoringBatteryOptimizations;

  /// Always true below Android 12. Without it the app falls back to inexact alarms (refresh every ~5 min).
  final bool canScheduleExactAlarms;

  /// Registered and the binding has not expired yet.
  final bool registered;
  final bool serviceRunning;

  /// 'registered' | 'failed' | 'unregistered' | 'unknown' (last PJSIP report).
  final String registrationState;
  final DateTime? lastRegisteredAt;
  final DateTime? registrationExpiresAt;

  /// Last time a reachability alarm woke the app.
  final DateTime? lastWakeupAt;
  final DateTime? lastTransportDropAt;
  final DateTime? nextAlarmAt;
  final String manufacturer;
  final OemFamily oemFamily;
  final int sdkInt;

  List<ReachabilityIssue> get issues => [
        if (!notificationsEnabled) ReachabilityIssue.notificationsDisabled,
        if (!canUseFullScreenIntent) ReachabilityIssue.fullScreenIntentDenied,
        if (!ignoringBatteryOptimizations) ReachabilityIssue.batteryOptimized,
        if (!canScheduleExactAlarms) ReachabilityIssue.exactAlarmsDenied,
        if (!serviceRunning) ReachabilityIssue.serviceStopped,
        if (!registered) ReachabilityIssue.notRegistered,
      ];

  bool get isFullyReachable => issues.isEmpty;
}
