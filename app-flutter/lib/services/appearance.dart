import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_store.dart';
import 'sip_channel.dart';

/// In-app "Erscheinungsbild" (Ich tab). Nachtwache is dark-first, so the
/// default is [dark]; [system] follows the phone. [wire] is what the native
/// side stores (ring/Appearance.kt).
enum AppAppearance {
  dark('dark', 'Dunkel', ThemeMode.dark),
  light('light', 'Hell', ThemeMode.light),
  system('system', 'Wie System', ThemeMode.system);

  const AppAppearance(this.wire, this.label, this.themeMode);

  final String wire;
  final String label;
  final ThemeMode themeMode;

  static const fallback = AppAppearance.dark;

  static AppAppearance fromWire(String? value) =>
      values.firstWhere((a) => a.wire == value, orElse: () => fallback);
}

/// Holds the appearance, persists it (SharedPreferences) and pushes it to the
/// native side. MaterialApp listens and switches live.
class AppearanceController extends ValueNotifier<AppAppearance> {
  AppearanceController({
    Future<SharedPreferences?> Function()? prefs,
    Future<void> Function(String mode)? pushNative,
  })  : _prefs = prefs ?? loadPrefs,
        _pushNative = pushNative ?? SipChannel.instance.setAppearance,
        super(AppAppearance.fallback);

  static final AppearanceController instance = AppearanceController();

  final Future<SharedPreferences?> Function() _prefs;
  final Future<void> Function(String mode) _pushNative;

  ThemeMode get themeMode => value.themeMode;

  /// Reads the stored choice and pushes it to native once (app start).
  Future<void> load() async {
    final prefs = await _prefs();
    value = AppAppearance.fromWire(prefs?.getString(StoreKeys.appearance));
    await _push();
  }

  Future<void> set(AppAppearance appearance) async {
    value = appearance;
    final prefs = await _prefs();
    await prefs?.setString(StoreKeys.appearance, appearance.wire);
    await _push();
  }

  Future<void> _push() async {
    try {
      await _pushNative(value.wire);
    } catch (e) {
      debugPrint('setAppearance failed: $e');
    }
  }
}
