import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/theme/app_colors.dart';
import 'package:ha_phone_test/theme/nw_shapes.dart';

void main() {
  test('brand gradient uses the spec stops at 135°', () {
    expect(NwColors.light.brandGradient.colors, const [Color(0xFF008BCF), Color(0xFF5FA92E)]);
    expect(NwColors.dark.brandGradient.colors, const [Color(0xFF0EA5E9), Color(0xFF89C940)]);
    for (final c in [NwColors.light, NwColors.dark]) {
      expect(c.brandGradient.begin, Alignment.topLeft);
      expect(c.brandGradient.end, Alignment.bottomRight);
    }
  });

  test('dark title gradient is the brand gradient, light uses darker AA stops', () {
    expect(NwColors.dark.brandTitle.colors, NwColors.dark.brandGradient.colors);
    expect(NwColors.light.brandTitle.colors, const [Color(0xFF0077B3), Color(0xFF4A8A22)]);
  });

  test('answer, end and door colours stay unchanged', () {
    expect(NwColors.dark.answer, const Color(0xFF2FBF71));
    expect(NwColors.dark.end, const Color(0xFFE5484D));
    expect(NwColors.dark.door, const Color(0xFFF5A524));
    expect(NwColors.light.answer, const Color(0xFF177E45));
    expect(NwColors.light.end, const Color(0xFFD92D32));
    expect(NwColors.light.door, const Color(0xFFA86500));
  });

  test('lerp light→dark interpolates the gradients (animated theme switch)', () {
    final mid = NwColors.light.lerp(NwColors.dark, 0.5);
    expect(mid.brandGradient.colors, hasLength(2));
    expect(mid.brandGradient.colors.first, Color.lerp(const Color(0xFF008BCF), const Color(0xFF0EA5E9), 0.5));
    expect(NwColors.light.lerp(NwColors.dark, 1).brandTitle.colors, NwColors.dark.brandTitle.colors);
    expect(NwColors.light.lerp(null, 0.5), same(NwColors.light));
  });

  test('copyWith keeps the gradient unless one is given', () {
    const other = LinearGradient(colors: [Colors.black, Colors.white]);
    expect(NwColors.dark.copyWith().brandGradient, NwColors.dark.brandGradient);
    expect(NwColors.dark.copyWith(brandGradient: other).brandGradient, other);
    expect(NwColors.dark.copyWith(brandInk: Colors.white).brandInk, Colors.white);
  });

  test('radii follow the rounder step of the 2026-10-05 spec', () {
    expect(NwRadius.card, 26);
    expect(NwRadius.cardLarge, 30);
    expect(NwRadius.control, 26);
    expect(NwRadius.dialKey, 26);
    expect(NwRadius.dialKeyCompact, 22);
    expect(NwRadius.button, 20);
    expect(NwRadius.field, 16);
    expect(NwRadius.row, 18);
    expect(NwRadius.sheet, 30);
    expect(NwRadius.dialButton, 26);
  });
}
