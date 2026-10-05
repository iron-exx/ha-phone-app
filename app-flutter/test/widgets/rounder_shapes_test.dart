import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/widgets/call_controls.dart';
import 'package:ha_phone_test/widgets/contact_tile.dart';
import 'package:ha_phone_test/widgets/dialpad_grid.dart';
import 'package:ha_phone_test/widgets/nw_widgets.dart';

BorderRadius r(double v) => BorderRadius.circular(v);

Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: Center(child: child))),
    );

void main() {
  test('theme shapes use the rounder radii', () {
    for (final t in [AppTheme.light(), AppTheme.dark()]) {
      expect((t.cardTheme.shape! as RoundedRectangleBorder).borderRadius, r(NwRadius.card));
      expect((t.dialogTheme.shape! as RoundedRectangleBorder).borderRadius, r(NwRadius.cardLarge));
      for (final style in [t.filledButtonTheme.style!, t.outlinedButtonTheme.style!, t.textButtonTheme.style!]) {
        expect((style.shape!.resolve({})! as RoundedRectangleBorder).borderRadius, r(NwRadius.button));
      }
      expect((t.inputDecorationTheme.border! as OutlineInputBorder).borderRadius, r(NwRadius.field));
    }
  });

  test('NwCard, NwIconButton and RowCallButton defaults', () {
    expect(const NwCard(child: SizedBox()).radius, NwRadius.card);
    expect(NwIconButton(icon: Icons.add, label: 'x', onPressed: () {}).radius, NwRadius.button);
  });

  testWidgets('RowCallButton is softer inside list rows', (tester) async {
    await pump(tester, RowCallButton(label: 'anrufen', onPressed: () {}));
    expect(tester.widget<NwIconButton>(find.byType(NwIconButton)).radius, NwRadius.row);
  });

  testWidgets('full-height dialpad keys use dialKey, compact keys dialKeyCompact', (tester) async {
    Iterable<BorderRadiusGeometry?> radii() => tester
        .widgetList<Material>(find.descendant(of: find.byType(DialpadGrid), matching: find.byType(Material)))
        .map((m) => m.borderRadius);

    await pump(tester, SizedBox(width: 320, child: DialpadGrid(onDigit: (_) {})));
    expect(radii(), hasLength(12));
    expect(radii().toSet(), {r(NwRadius.dialKey)});

    await pump(tester, SizedBox(width: 320, child: DialpadGrid(onDigit: (_) {}, keySize: 52)));
    expect(radii().toSet(), {r(NwRadius.dialKeyCompact)});
  });

  testWidgets('in-call control tile uses the control radius', (tester) async {
    await pump(tester, SizedBox(width: 110, child: CallControlButton(icon: Icons.mic_off, label: 'Stumm', onPressed: () {})));
    final tile = find.byWidgetPredicate((w) =>
        w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).borderRadius == r(NwRadius.control));
    expect(tile, findsOneWidget);
  });

  test('large cards and row ink read NwRadius instead of literals', () {
    String src(String p) => File(p).readAsStringSync();
    expect(src('lib/widgets/door_card.dart'), contains('radius: NwRadius.cardLarge'));
    expect(src('lib/widgets/call_video_card.dart'), contains('BorderRadius.circular(NwRadius.cardLarge)'));
    expect(src('lib/widgets/timeline_row.dart'), contains('BorderRadius.circular(NwRadius.row)'));
    expect(src('lib/widgets/contact_tile.dart'), contains('BorderRadius.circular(NwRadius.row)'));
    expect(src('lib/widgets/door_open_button.dart'), contains('BorderRadius.circular(NwRadius.button)'));
  });
}
