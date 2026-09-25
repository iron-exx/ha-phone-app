import 'package:flutter/material.dart';

import '../services/appearance.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Small sheet for "Erscheinungsbild": Dunkel · Hell · Wie System. Applies
/// at once (the app behind the sheet switches live).
class AppearanceSheet extends StatelessWidget {
  const AppearanceSheet({super.key, required this.controller});

  final AppearanceController controller;

  static Future<void> show(BuildContext context, AppearanceController controller) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => AppearanceSheet(controller: controller),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ValueListenableBuilder<AppAppearance>(
          valueListenable: controller,
          builder: (context, current, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Erscheinungsbild', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SegmentedButton<AppAppearance>(
                key: const Key('appearance-segments'),
                showSelectedIcon: false,
                segments: [
                  for (final a in AppAppearance.values)
                    ButtonSegment(
                      value: a,
                      label: Text(a.label, key: Key('appearance-${a.wire}')),
                      icon: Icon(_icon(a)),
                    ),
                ],
                selected: {current},
                onSelectionChanged: (s) => controller.set(s.first),
              ),
              const SizedBox(height: 12),
              Text(
                current == AppAppearance.system
                    ? 'Folgt der Einstellung deines Handys.'
                    : 'Gilt für die ganze App, auch für den Klingelbildschirm.',
                style: NwType.meta.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _icon(AppAppearance a) => switch (a) {
        AppAppearance.dark => Icons.dark_mode_outlined,
        AppAppearance.light => Icons.light_mode_outlined,
        AppAppearance.system => Icons.brightness_auto_outlined,
      };
}
