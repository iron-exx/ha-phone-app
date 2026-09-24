import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/theme/app_colors.dart';

/// WCAG 2.x contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// AA for normal-size text.
const kTextContrast = 4.5;

void main() {
  for (final (name, c) in [('dark', NwColors.dark), ('light', NwColors.light)]) {
    group('$name theme', () {
      test('text roles on ground, surface and raised reach 4.5:1', () {
        for (final (role, fg) in [('text', c.text), ('muted', c.muted), ('faint', c.faint)]) {
          for (final (bgName, bg) in [('ground', c.ground), ('surface', c.surface), ('raised', c.raised)]) {
            expect(contrast(fg, bg), greaterThanOrEqualTo(kTextContrast), reason: '$role on $bgName');
          }
        }
      });

      test('ink on blue, door, answer and the text-label end fill reach 4.5:1', () {
        for (final (role, ink, fill) in [
          ('blueInk/blue', c.blueInk, c.blue),
          ('doorInk/door', c.doorInk, c.door),
          ('answerInk/answer', c.answerInk, c.answer),
          ('endInk/endStrong', c.endInk, c.endStrong),
        ]) {
          expect(contrast(ink, fill), greaterThanOrEqualTo(kTextContrast), reason: role);
        }
      });

      test('soft chips: text on its soft fill reaches 4.5:1', () {
        expect(contrast(c.blueOnSoft, c.blueSoft), greaterThanOrEqualTo(kTextContrast));
        expect(contrast(c.okText, c.okSurface), greaterThanOrEqualTo(kTextContrast));
      });
    });
  }

  test('icon-only hang-up fill (dark end) stays ≥ 3:1 against white glyphs', () {
    expect(contrast(NwColors.dark.endInk, NwColors.dark.end), greaterThanOrEqualTo(3));
  });
}
