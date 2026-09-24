import 'package:flutter/material.dart';

import '../screens/forwarding_screen.dart';
import '../screens/reachability_screen.dart';
import '../services/directory_repository.dart';
import '../services/forwarding_repository.dart';
import '../services/presence_repository.dart';
import '../services/reachability_repository.dart';
import '../services/ring_settings_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'nw_widgets.dart';
import 'status_panel.dart';

/// Bottom sheet behind the Start pill: the full [StatusPanel] plus a link to
/// "Erreichbarkeit" (amber when something is not ok).
class StatusSheet extends StatelessWidget {
  const StatusSheet({
    super.key,
    this.controller,
    this.reachability,
    this.directory,
    this.presence,
    this.forwarding,
    this.ring,
  });

  final ScrollController? controller;
  final ReachabilityRepository? reachability;
  final DirectoryRepository? directory;
  final PresenceRepository? presence;
  final ForwardingRepository? forwarding;
  final RingSettingsRepository? ring;

  static Future<void> show(
    BuildContext context, {
    ReachabilityRepository? reachability,
    DirectoryRepository? directory,
    PresenceRepository? presence,
    ForwardingRepository? forwarding,
    RingSettingsRepository? ring,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (context, controller) => StatusSheet(
            controller: controller,
            reachability: reachability,
            directory: directory,
            presence: presence,
            forwarding: forwarding,
            ring: ring,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    void push(Widget screen) {
      navigator.pop();
      navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
    }

    final reach = reachability ?? ReachabilityRepository.instance;
    return SafeArea(
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          StatusPanel(
            directory: directory,
            presence: presence,
            forwarding: forwarding,
            ring: ring,
            onOpenForwarding: () => push(ForwardingScreen(repository: forwarding, directory: directory, presence: presence)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: ListenableBuilder(
              listenable: reach,
              builder: (context, _) => ReachabilityLinkCard(
                hasProblems: reach.hasProblems,
                onTap: () => push(ReachabilityScreen(repository: reachability)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Erreichbarkeit prüfen" row with an amber dot when something is not ok.
class ReachabilityLinkCard extends StatelessWidget {
  const ReachabilityLinkCard({super.key, required this.hasProblems, required this.onTap});

  final bool hasProblems;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return Semantics(
      button: true,
      label: hasProblems ? 'Erreichbarkeit: nicht alles in Ordnung' : 'Erreichbarkeit prüfen',
      excludeSemantics: true,
      child: NwCard(
        key: const Key('status-reachability'),
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: onTap,
        child: Row(
          children: [
            Icon(Icons.verified_user_outlined, size: 20, color: hasProblems ? c.door : c.answer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasProblems ? 'Erreichbarkeit: bitte prüfen' : 'Erreichbarkeit prüfen',
                style: NwType.rowTitle.copyWith(color: c.text, fontSize: 14),
              ),
            ),
            if (hasProblems) ...[
              Container(
                key: const Key('reach-warning-dot'),
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: c.door, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right, size: 18, color: c.faint),
          ],
        ),
      ),
    );
  }
}
