import 'dart:ui' show Locale;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local preference keys for the whole application.
///
/// These settings survive logout/login and app restarts because they describe
/// the *device*, not the session. They are intentionally separate from the
/// auth token store (which must be cleared on sign-out).
class PrefKeys {
  PrefKeys._();

  static const String themeMode = 'sw.app.theme_mode';
  static const String locale = 'sw.app.locale';
}

/// Persisted /[PrefKeys.themeMode] values.
enum StoredThemeMode {
  system('system'),
  light('light'),
  dark('dark');

  const StoredThemeMode(this.raw);
  final String raw;

  static StoredThemeMode parse(String? raw) {
    for (final mode in StoredThemeMode.values) {
      if (mode.raw == raw) return mode;
    }
    return StoredThemeMode.system;
  }
}

/// Thin typed wrapper over [SharedPreferences] for the device settings.
///
/// `AppPreferences.memory()` gives an in-memory instance for tests /
/// platforms without a plugin channel.
class AppPreferences {
  AppPreferences._(this._prefs) {
    if (_prefs != null) {
      _cache[PrefKeys.themeMode] =
          _prefs.getString(PrefKeys.themeMode) ?? StoredThemeMode.system.raw;
      _cache[PrefKeys.locale] = _prefs.getString(PrefKeys.locale) ?? '';
    }
  }

  /// Load the real device settings (plugin-backed).
  ///
  /// A short timeout guards boot: a slow/hung plugin channel (widget tests,
  /// exotic platforms) degrades to an in-memory snapshot instead of stalling
  /// the session restore behind the splash.
  static Future<AppPreferences> load() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(milliseconds: 800));
      return AppPreferences._(prefs);
    } catch (_) {
      return AppPreferences.memory();
    }
  }

  /// In-memory instance for tests / non-plugin environments.
  static AppPreferences memory() => AppPreferences._(null);

  final SharedPreferences? _prefs;
  final Map<String, Object> _cache = {};

  /// Stored theme preference (defaults to `system`).
  StoredThemeMode get storedThemeMode =>
      StoredThemeMode.parse(_cache[PrefKeys.themeMode] as String?);

  Future<void> setThemeMode(StoredThemeMode mode) async {
    _cache[PrefKeys.themeMode] = mode.raw;
    await _prefs?.setString(PrefKeys.themeMode, mode.raw);
  }

  /// Stored language tag (`en` / `sw`) or `null` when "follow system".
  String? get storedLanguageTag {
    final raw = _cache[PrefKeys.locale] as String?;
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  Future<void> setLanguageTag(String? tag) async {
    _cache[PrefKeys.locale] = tag ?? '';
    final raw = (tag == null || tag.isEmpty) ? null : tag;
    if (raw == null) {
      await _prefs?.remove(PrefKeys.locale);
    } else {
      await _prefs?.setString(PrefKeys.locale, raw);
    }
  }
}

/// Flutter [ThemeMode] from the stored enum.
ThemeMode storedToFlutter(StoredThemeMode mode) {
  switch (mode) {
    case StoredThemeMode.light:
      return ThemeMode.light;
    case StoredThemeMode.dark:
      return ThemeMode.dark;
    case StoredThemeMode.system:
      return ThemeMode.system;
  }
}

StoredThemeMode flutterToStored(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return StoredThemeMode.light;
    case ThemeMode.dark:
      return StoredThemeMode.dark;
    case ThemeMode.system:
      return StoredThemeMode.system;
  }
}

/// Supported app languages (ISO-639-1 tags) in display order.
const List<String> kAppLanguageTags = ['en', 'sw'];

/// Fallback for unsupported devices / corrupted stored tags.
const String kDefaultLanguageTag = 'en';

bool isSupportedLanguageTag(String? tag) =>
    tag != null && kAppLanguageTags.contains(tag);

/// Map a stored language tag to a [Locale]; empty/unknown falls back to the
/// default so the platform never sees an empty language code.
Locale tagToLocale(String? tag) =>
    Locale((tag == null || tag.isEmpty) ? kDefaultLanguageTag : tag);