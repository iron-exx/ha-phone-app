import 'package:flutter/material.dart';

import '../services/app_navigation.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'nw_widgets.dart';

/// Nachtwache bottom bar: Start · Verlauf · (Wählen, raised blue 68 dp
/// button with a soft glow) · Kontakte · Ich. [historyBadge] is the red
/// count on Verlauf (missed calls + new voicemails).
class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.selected, required this.onSelect, this.historyBadge = 0});

  final AppTab selected;
  final ValueChanged<AppTab> onSelect;
  final int historyBadge;

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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _tab(context, AppTab.start, 'Start', Icons.home_outlined, Icons.home_rounded),
                _tab(context, AppTab.history, 'Verlauf', Icons.history, Icons.history, badge: historyBadge),
                _dialButton(context),
                _tab(context, AppTab.contacts, 'Kontakte', Icons.people_outline, Icons.people_rounded),
                _tab(context, AppTab.me, 'Ich', Icons.person_outline, Icons.person_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, AppTab tab, String label, IconData icon, IconData selectedIcon, {int badge = 0}) {
    final c = context.nw;
    final on = selected == tab;
    final semantic = badge > 0 ? '$label, $badge neu' : label;
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
          borderRadius: BorderRadius.circular(18),
          onTap: () => onSelect(tab),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 4),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Semantics(
        button: true,
        selected: on,
        label: 'Wählen',
        onTap: () => onSelect(AppTab.dial),
        excludeSemantics: true,
        child: Container(
          key: const ValueKey('tab-dial'),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: c.blue.withOpacity(0.28), blurRadius: 30, offset: const Offset(0, 10))],
          ),
          child: Material(
            color: c.blue,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => onSelect(AppTab.dial),
              child: SizedBox(
                width: 68,
                height: 68,
                child: Icon(Icons.dialpad_rounded, size: 28, color: c.blueInk),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
