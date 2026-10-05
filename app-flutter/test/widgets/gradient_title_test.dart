import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/widgets/nw_widgets.dart';

Future<void> pumpHeader(WidgetTester tester, {double textScale = 1, ThemeData? theme}) async {
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
      body: PageHeader('Erreichbarkeit', actions: [
        NwIconButton(icon: Icons.tune, label: 'Filter', onPressed: () {}),
      ]),
    ),
  ));
}

void main() {
  testWidgets('page title is painted through a gradient ShaderMask', (tester) async {
    await pumpHeader(tester);
    final mask = find.ancestor(of: find.text('Erreichbarkeit'), matching: find.byType(ShaderMask));
    expect(mask, findsOneWidget);
    expect(tester.widget<ShaderMask>(mask).blendMode, BlendMode.srcIn);
    // srcIn needs an opaque glyph colour; the gradient supplies the hue.
    expect(tester.widget<Text>(find.text('Erreichbarkeit')).style!.color, Colors.white);
    expect(tester.widget<Text>(find.text('Erreichbarkeit')).style!.fontSize, NwType.pageTitle.fontSize);
  });

  testWidgets('TalkBack still reads the title as a header', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHeader(tester, theme: AppTheme.dark());
    expect(tester.getSemantics(find.text('Erreichbarkeit')), containsSemantics(label: 'Erreichbarkeit', isHeader: true));
    handle.dispose();
  });

  testWidgets('title with action fits at 200 % text on 360 dp', (tester) async {
    await pumpHeader(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Erreichbarkeit'), findsOneWidget);
    expect(find.byTooltip('Filter'), findsOneWidget);
  });

  test('gradient text refuses sizes below 24 px', () {
    expect(() => NwGradientText('klein', style: const TextStyle(fontSize: 15)), throwsAssertionError);
    expect(() => NwGradientText('groß', style: const TextStyle(fontSize: 24)), returnsNormally);
  });
}
