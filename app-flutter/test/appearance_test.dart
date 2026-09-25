import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/services/appearance.dart';
import 'package:ha_phone_test/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late List<String> pushed;

  AppearanceController controller({bool failingPush = false}) => AppearanceController(
        prefs: SharedPreferences.getInstance,
        pushNative: (mode) async {
          if (failingPush) throw StateError('no native side');
          pushed.add(mode);
        },
      );

  setUp(() {
    pushed = [];
    SharedPreferences.setMockInitialValues({});
  });

  test('default is Dunkel (dark-first), even before load', () {
    final c = controller();
    expect(c.value, AppAppearance.dark);
    expect(c.themeMode, ThemeMode.dark);
  });

  test('load without stored value stays dark and pushes it to native once', () async {
    final c = controller();
    await c.load();
    expect(c.value, AppAppearance.dark);
    expect(pushed, ['dark']);
  });

  test('load restores the stored choice', () async {
    SharedPreferences.setMockInitialValues({StoreKeys.appearance: 'light'});
    final c = controller();
    await c.load();
    expect(c.value, AppAppearance.light);
    expect(c.themeMode, ThemeMode.light);
    expect(pushed, ['light']);
  });

  test('unknown stored value falls back to dark', () async {
    SharedPreferences.setMockInitialValues({StoreKeys.appearance: 'purple'});
    final c = controller();
    await c.load();
    expect(c.value, AppAppearance.dark);
  });

  test('set persists, notifies and pushes to native', () async {
    final c = controller();
    var notified = 0;
    c.addListener(() => notified++);
    await c.set(AppAppearance.system);
    expect(c.themeMode, ThemeMode.system);
    expect(notified, 1);
    expect(pushed, ['system']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StoreKeys.appearance), 'system');

    // A fresh controller (next app start) reads it back.
    final next = controller();
    await next.load();
    expect(next.value, AppAppearance.system);
  });

  test('a failing native push does not break the setting', () async {
    final c = controller(failingPush: true);
    await c.set(AppAppearance.light);
    expect(c.value, AppAppearance.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StoreKeys.appearance), 'light');
  });

  test('wire values and labels', () {
    expect(AppAppearance.values.map((a) => a.wire), ['dark', 'light', 'system']);
    expect(AppAppearance.values.map((a) => a.label), ['Dunkel', 'Hell', 'Wie System']);
    for (final a in AppAppearance.values) {
      expect(AppAppearance.fromWire(a.wire), a);
    }
    expect(AppAppearance.fromWire(null), AppAppearance.dark);
  });
}
