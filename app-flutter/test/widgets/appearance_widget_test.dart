import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_phone_test/main.dart';
import 'package:ha_phone_test/services/appearance.dart';
import 'package:ha_phone_test/services/local_store.dart';
import 'package:ha_phone_test/theme/app_theme.dart';
import 'package:ha_phone_test/widgets/appearance_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_sip.dart';

void main() {
  late FakeSip sip;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sip = FakeSip({'hasValidCredentials': (_) => false})..install();
  });
  tearDown(() => sip.uninstall());

  AppearanceController newController() => AppearanceController(prefs: SharedPreferences.getInstance);

  MaterialApp app(WidgetTester tester) => tester.widget<MaterialApp>(find.byType(MaterialApp));

  testWidgets('HAPhoneApp starts dark while the phone is light and pushes it to native', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final appearance = newController();
    await tester.pumpWidget(HAPhoneApp(appearance: appearance));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();

    expect(app(tester).themeMode, ThemeMode.dark);
    final ctx = tester.element(find.byType(Navigator).first);
    expect(Theme.of(ctx).brightness, Brightness.dark);
    expect(sip.callsTo('setAppearance').map((c) => c.arguments), contains('dark'));
  });

  testWidgets('switching updates MaterialApp.themeMode live, bars follow the app theme', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final appearance = newController();
    await tester.pumpWidget(HAPhoneApp(appearance: appearance));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();

    await tester.runAsync(() => appearance.set(AppAppearance.light));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // AnimatedTheme
    expect(app(tester).themeMode, ThemeMode.light);
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byWidgetPredicate((w) => w is AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    // System is dark, app is Hell: dark icons for the light theme.
    expect(region.value.statusBarIconBrightness, Brightness.dark);

    await tester.runAsync(() => appearance.set(AppAppearance.system));
    await tester.pump();
    expect(app(tester).themeMode, ThemeMode.system);
    expect(sip.callsTo('setAppearance').map((c) => c.arguments), containsAllInOrder(['light', 'system']));
  });

  testWidgets('sheet: tapping Hell and back to Dunkel applies and persists', (tester) async {
    final appearance = newController();
    await tester.pumpWidget(ValueListenableBuilder<AppAppearance>(
      valueListenable: appearance,
      builder: (context, a, _) => MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: a.themeMode,
        home: Scaffold(body: AppearanceSheet(controller: appearance)),
      ),
    ));
    expect(find.text('Erscheinungsbild'), findsOneWidget);
    expect(find.text('Dunkel'), findsOneWidget);
    expect(find.text('Hell'), findsOneWidget);
    expect(find.text('Wie System'), findsOneWidget);
    var ctx = tester.element(find.byType(AppearanceSheet));
    expect(Theme.of(ctx).brightness, Brightness.dark);

    await tester.tap(find.byKey(const Key('appearance-light')));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();
    expect(appearance.value, AppAppearance.light);
    ctx = tester.element(find.byType(AppearanceSheet));
    expect(Theme.of(ctx).brightness, Brightness.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StoreKeys.appearance), 'light');

    await tester.tap(find.byKey(const Key('appearance-dark')));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();
    expect(appearance.value, AppAppearance.dark);
    expect(prefs.getString(StoreKeys.appearance), 'dark');
  });
}
