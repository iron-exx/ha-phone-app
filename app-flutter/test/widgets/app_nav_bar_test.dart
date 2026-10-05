import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/app_navigation.dart';
import 'package:ha_phone_test/theme/app_colors.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/widgets/app_nav_bar.dart';

import '../helpers/semantics.dart';

Future<List<AppTab>> pumpBar(
  WidgetTester tester, {
  AppTab selected = AppTab.history,
  ThemeData? theme,
  double textScale = 1,
}) async {
  final taps = <AppTab>[];
  tester.view.physicalSize = const Size(1080, 2340); // 360 × 780 dp
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      bottomNavigationBar: AppNavBar(selected: selected, onSelect: taps.add, historyBadge: 3, meWarning: true),
    ),
  ));
  return taps;
}

Finder indicators() => find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('tab-indicator-'),
    );

void main() {
  for (final (name, theme, c) in [('light', AppTheme.light(), NwColors.light), ('dark', AppTheme.dark(), NwColors.dark)]) {
    group('$name theme', () {
      testWidgets('bar is a floating stadium pill on surface', (tester) async {
        await pumpBar(tester, theme: theme);
        final pill = tester.widget<DecoratedBox>(find.byKey(const ValueKey('nav-pill')));
        final deco = pill.decoration as ShapeDecoration;
        expect(deco.shape, isA<StadiumBorder>());
        expect(deco.color, c.surface);
      });

      testWidgets('dial button is the brand gradient with brandInk icon, no blue glow', (tester) async {
        await pumpBar(tester, theme: theme);
        final dial = find.byKey(const ValueKey('tab-dial'));
        final ink = tester.widget<Ink>(find.descendant(of: dial, matching: find.byType(Ink)));
        expect((ink.decoration! as BoxDecoration).gradient, c.brandGradient);
        expect((ink.decoration! as BoxDecoration).borderRadius, BorderRadius.circular(NwRadius.dialButton));
        final icon = tester.widget<Icon>(find.descendant(of: dial, matching: find.byIcon(Icons.dialpad_rounded)));
        expect(icon.color, c.brandInk);
        final shadows = (tester.widget<DecoratedBox>(dial).decoration as BoxDecoration).boxShadow ?? const [];
        expect(shadows.map((s) => s.color), isNot(contains(c.blue.withOpacity(0.28))));
      });

      testWidgets('only the active tab shows the gradient bar', (tester) async {
        await pumpBar(tester, theme: theme);
        expect(indicators(), findsOneWidget);
        final bar = tester.widget<Container>(find.byKey(const ValueKey('tab-indicator-history')));
        expect((bar.decoration! as BoxDecoration).gradient, c.brandGradient);
      });
    });
  }

  testWidgets('dial selected: no tab bar indicator', (tester) async {
    await pumpBar(tester, selected: AppTab.dial);
    expect(indicators(), findsNothing);
  });

  testWidgets('badge and amber warning dot are unchanged', (tester) async {
    await pumpBar(tester);
    expect(find.byKey(const ValueKey('badge-history')), findsOneWidget);
    final dot = tester.widget<Container>(find.byKey(const ValueKey('warning-me')));
    expect((dot.decoration! as BoxDecoration).color, NwColors.light.door);
  });

  testWidgets('fits at 200 % system text on 360 dp', (tester) async {
    await pumpBar(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Kontakte'), findsOneWidget);
  });

  testWidgets('TalkBack can open Wählen', (tester) async {
    final handle = tester.ensureSemantics();
    final taps = await pumpBar(tester);
    semanticsAction(tester, find.bySemanticsLabel('Wählen'));
    expect(taps, [AppTab.dial]);
    handle.dispose();
  });
}
