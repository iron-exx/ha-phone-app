import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/theme/app_colors.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/widgets/nw_widgets.dart';

Finder gradientInk() => find.byWidgetPredicate(
      (w) => w is Ink && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).gradient != null,
    );

Material buttonMaterial(WidgetTester tester) => tester.widget<Material>(
      find.descendant(of: find.byType(FilledButton), matching: find.byType(Material)).first,
    );

Future<void> pump(WidgetTester tester, Widget child, ThemeData theme) => tester.pumpWidget(
      MaterialApp(theme: theme, home: Scaffold(body: Center(child: child))),
    );

void main() {
  for (final (name, theme, c) in [('light', AppTheme.light(), NwColors.light), ('dark', AppTheme.dark(), NwColors.dark)]) {
    group('$name theme', () {
      testWidgets('primary FilledButton paints the brand gradient with brandInk text', (tester) async {
        await pump(tester, FilledButton(onPressed: () {}, child: const Text('Speichern')), theme);
        expect(gradientInk(), findsOneWidget);
        final deco = tester.widget<Ink>(gradientInk()).decoration! as BoxDecoration;
        expect(deco.gradient, c.brandGradient);
        expect(deco.borderRadius, BorderRadius.circular(NwRadius.button));
        final label = tester.widget<RichText>(
          find.descendant(of: find.byType(FilledButton), matching: find.byType(RichText)),
        );
        expect(label.text.style!.color, c.brandInk);
      });

      testWidgets('disabled primary button is flat raised, no gradient', (tester) async {
        await pump(tester, const FilledButton(onPressed: null, child: Text('Speichern')), theme);
        expect(gradientInk(), findsNothing);
        expect(buttonMaterial(tester).color, c.raised);
      });

      testWidgets('door pill button keeps its amber fill', (tester) async {
        await pump(
          tester,
          NwPillButton(label: 'Tür öffnen', onPressed: () {}, background: c.door, foreground: c.doorInk),
          theme,
        );
        expect(gradientInk(), findsNothing);
        expect(buttonMaterial(tester).color, c.door);
      });

      testWidgets('answer-coloured FilledButton with NwButtons.solid keeps green', (tester) async {
        await pump(
          tester,
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.answer,
              foregroundColor: c.answerInk,
              backgroundBuilder: NwButtons.solid,
            ),
            onPressed: () {},
            child: const Text('Annehmen'),
          ),
          theme,
        );
        expect(gradientInk(), findsNothing);
        expect(buttonMaterial(tester).color, c.answer);
      });
    });
  }
}
