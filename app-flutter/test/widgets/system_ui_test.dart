import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/theme/app_theme.dart';

void main() {
  test('light theme: dark status/nav bar icons on transparent bars', () {
    final s = AppTheme.overlayStyle(Brightness.light);
    expect(s.statusBarIconBrightness, Brightness.dark);
    expect(s.systemNavigationBarIconBrightness, Brightness.dark);
    expect(s.statusBarColor, Colors.transparent);
    expect(s.systemNavigationBarColor, Colors.transparent);
    expect(AppTheme.light().appBarTheme.systemOverlayStyle, s);
  });

  test('dark theme: light icons', () {
    final s = AppTheme.overlayStyle(Brightness.dark);
    expect(s.statusBarIconBrightness, Brightness.light);
    expect(s.systemNavigationBarIconBrightness, Brightness.light);
    expect(AppTheme.dark().appBarTheme.systemOverlayStyle, s);
  });

  for (final brightness in Brightness.values) {
    testWidgets('NwSystemUi annotates screens without AppBar ($brightness)', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        builder: (context, child) => NwSystemUi(child: child!),
        home: const Scaffold(body: SizedBox.expand()),
      ));
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byWidgetPredicate((w) => w is AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      final icons = brightness == Brightness.light ? Brightness.dark : Brightness.light;
      expect(region.value.statusBarIconBrightness, icons);
      expect(region.value.systemNavigationBarIconBrightness, icons);
    });
  }
}
