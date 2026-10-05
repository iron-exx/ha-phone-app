import 'package:flutter/material.dart';

import '../services/app_navigation.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'nw_widgets.dart';

/// Nachtwache bottom bar as a floating pill: Start · Verlauf · (Wählen,
/// 64 dp button in the brand gradient with a light green glow) · Kontakte ·
/// Ich. The active tab shows a tinted icon pill plus a short gradient bar.
/// [historyBadge] is the red count on Verlauf (missed calls + new voicemails).
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.selected,
    required this.onSelect,
    this.historyBadge = 0,
    this.meWarning = false,
  });

  final AppTab selected;
  final ValueChanged<AppTab> onSelect;
  final int historyBadge;

  /// Small amber dot on Ich: something keeps calls from ringing (Erreichbarkeit).
  final bool meWarning;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    // Labels grow with the system font up to 1.4×; beyond that the bar would
    // eat the screen (the icons and TalkBack labels carry the meaning).
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [c.ground, c.ground, c.ground.withOpacity(0)],
            stops: const [0, 0.7, 1],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: DecoratedBox(
              key: const ValueKey('nav-pill'),
              decoration: ShapeDecoration(
                color: c.surface,
                shape: StadiumBorder(side: BorderSide(color: c.stroke)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    _tab(context, AppTab.start, 'Start', Icons.home_outlined, Icons.home_rounded),
                    _tab(context, AppTab.history, 'Verlauf', Icons.history, Icons.history, badge: historyBadge),
                    _dialButton(context),
                    _tab(context, AppTab.contacts, 'Kontakte', Icons.people_outline, Icons.people_rounded),
                    _tab(context, AppTab.me, 'Ich', Icons.person_outline, Icons.person_rounded, warning: meWarning),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, AppTab tab, String label, IconData icon, IconData selectedIcon,
      {int badge = 0, bool warning = false}) {
    final c = context.nw;
    final on = selected == tab;
    final semantic = badge > 0
        ? '$label, $badge neu'
        : warning
            ? '$label, Erreichbarkeit prüfen'
            : label;
    return Expanded(
      child: Semantics(
        button: true,
        selected: on,
        label: semantic,
        // excludeSemantics drops the InkWell's action, so TalkBack needs it here.
        onTap: () => onSelect(tab),
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('tab-${tab.name}'),
          borderRadius: BorderRadius.circular(NwRadius.row),
          onTap: () => onSelect(tab),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 2),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 52,
                      height: 30,
                      decoration: BoxDecoration(
                        color: on ? c.blueSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(on ? selectedIcon : icon, size: 22, color: on ? c.blue : c.faint),
                    ),
                    if (badge > 0)
                      Positioned(
                        left: 32,
                        top: -6,
                        child: CountBadge(badge, key: ValueKey('badge-${tab.name}')),
                      ),
                    if (warning)
                      Positioned(
                        right: 10,
                        top: 2,
                        child: Container(
                          key: ValueKey('warning-${tab.name}'),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: c.door,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.ground, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NwFonts.ui,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: on ? c.text : c.faint,
                  ),
                ),
                const SizedBox(height: 3),
                on
                    ? Container(
                        key: ValueKey('tab-indicator-${tab.name}'),
                        width: 18,
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: c.brandGradient,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    : const SizedBox(height: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialButton(BuildContext context) {
    final c = context.nw;
    final on = selected == AppTab.dial;
    final radius = BorderRadius.circular(NwRadius.dialButton);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        selected: on,
        label: 'Wählen',
        onTap: () => onSelect(AppTab.dial),
        excludeSemantics: true,
        child: DecoratedBox(
          key: const ValueKey('tab-dial'),
          decoration: BoxDecoration(
            borderRadius: radius,
            // Light green glow (spec §2), replaces the blue one.
            boxShadow: [
              BoxShadow(
                color: c.brandGradient.colors.last.withOpacity(0.25),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Ink(
              decoration: BoxDecoration(gradient: c.brandGradient, borderRadius: radius),
              child: InkWell(
                borderRadius: radius,
                onTap: () => onSelect(AppTab.dial),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Icon(Icons.dialpad_rounded, size: 28, color: c.brandInk),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
