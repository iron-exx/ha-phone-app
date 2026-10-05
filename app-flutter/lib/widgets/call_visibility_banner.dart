import 'package:flutter/material.dart';

import '../models/reachability.dart';
import '../services/reachability_repository.dart';
import '../services/reachability_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'nw_widgets.dart';

/// Start-page warning for the two permissions without which a call (or the door)
/// rings in SIP but never shows on the phone. Sideloaded on Android 14+, the
/// full-screen permission is off by default. All other reachability issues stay
/// on the Erreichbarkeit screen.
class CallVisibilityBanner extends StatelessWidget {
  const CallVisibilityBanner({super.key, required this.reachability, this.service});

  final ReachabilityRepository reachability;
  final ReachabilityService? service;

  static const texts = {
    ReachabilityIssue.notificationsDisabled: (
      'Benachrichtigungen sind aus',
      'Anrufe und die Türklingel erscheinen auf diesem Handy nicht.',
    ),
    ReachabilityIssue.fullScreenIntentDenied: (
      'Anrufe im Vollbild nicht erlaubt',
      'Bei gesperrtem Handy geht der Bildschirm beim Klingeln nicht an.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: reachability,
      builder: (context, _) {
        final issue = callVisibilityIssue(reachability);
        if (issue == null) return const SizedBox.shrink();
        final (title, detail) = texts[issue]!;
        final c = context.nw;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: NwCard(
            key: const Key('call-visibility-banner'),
            radius: NwRadius.cardSmall,
            color: c.doorSoft,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.notifications_off_outlined, color: c.door, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: NwType.rowTitle.copyWith(color: c.text, fontSize: 13.5, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(detail, style: NwType.meta.copyWith(color: c.muted, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    await (service ?? ReachabilityService.instance).openSettings(issue.settingsPage!);
                  },
                  child: const Text('Erlauben'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The first issue that keeps calls from showing (null: calls can appear).
ReachabilityIssue? callVisibilityIssue(ReachabilityRepository reachability) =>
    (reachability.snapshot?.issues ?? const <ReachabilityIssue>[])
        .where(CallVisibilityBanner.texts.containsKey)
        .firstOrNull;

/// Asks once per app start (a fresh install or an update always starts the app anew):
/// Android resets the full-screen permission of a sideloaded app on update, and the
/// start-page card alone was easy to miss. "Erlauben" opens the matching settings page.
class CallVisibilityPrompt {
  CallVisibilityPrompt._();

  static bool _asked = false;

  @visibleForTesting
  static void resetForTest() => _asked = false;

  static Future<void> maybeAsk(BuildContext context, ReachabilityRepository reachability,
      {ReachabilityService? service}) async {
    final issue = callVisibilityIssue(reachability);
    if (_asked || issue == null || !context.mounted) return;
    _asked = true;
    final (title, detail) = CallVisibilityBanner.texts[issue]!;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('call-visibility-dialog'),
        title: Text(title),
        content: Text('$detail\n\nNach einem App-Update setzt Android diese Erlaubnis manchmal zurück.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Später')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Erlauben')),
        ],
      ),
    );
    if (allow == true) await (service ?? ReachabilityService.instance).openSettings(issue.settingsPage!);
  }
}
