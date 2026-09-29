import 'package:flutter/material.dart';

import '../prefs/app_preferences.dart';

/// App-wide theme mode (Light / Dark / System) with device persistence.
///
/// * Defaults to `ThemeMode.system` and follows the platform setting.
/// * The choice is stored per-device (`shared_preferences`), so it survives
///   app restarts and logout/login.
/// * Exposed to the widget tree through [ThemeScope]; any surface may change
///   it via [AppThemeModeScope.of] -> [setMode].
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController(this._prefs) : super(storedToFlutter(_prefs.storedThemeMode));

  AppPreferences _prefs;

  /// Persisted raw mode, for prefs round-trips.
  StoredThemeMode get storedMode => flutterToStored(value);

  /// Swap in the device-backed preferences after async load and re-seed the
  /// value, so writes go to real storage (used at app boot).
  void reload(AppPreferences next) {
    _prefs = next;
    value = storedToFlutter(_prefs.storedThemeMode);
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == value) return;
    value = mode;
    await _prefs.setThemeMode(flutterToStored(mode));
  }

  Future<void> setStored(StoredThemeMode mode) async {
    final next = storedToFlutter(mode);
    if (next == value) return;
    value = next;
    await _prefs.setThemeMode(mode);
  }
}

/// Inherited access to the app [ThemeController].
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'No ThemeScope found in widget tree.');
    return scope!.notifier!;
  }

  static ThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.notifier;
}