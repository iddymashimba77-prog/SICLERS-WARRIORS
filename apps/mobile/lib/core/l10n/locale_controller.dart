import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/app_localizations.dart';
import '../prefs/app_preferences.dart';

/// App-wide language choice (English / Kiswahili / follow the device).
///
/// * `null` value → follow the system locale (English falls back when the
///   device language is unsupported).
/// * A stored tag (`en` / `sw`) is persisted device-wide and applies to every
///   screen, ahead of the system setting.
/// * [LocaleScope] is an [InheritedNotifier]: widgets rebuild when the user
///   switches language, and [MaterialApp.locale] is re-driven from [value].
class LocaleController extends ValueNotifier<Locale?> {
  LocaleController(this._prefs) : super(null);

  AppPreferences _prefs;

  /// Swap in the device-backed preferences after async load and re-seed the
  /// value (used at app boot). A cleared tag re-enables "follow device".
  void reload(AppPreferences next) {
    _prefs = next;
    final stored = _prefs.storedLanguageTag;
    value = (stored == null || stored.isEmpty) ? null : tagToLocale(stored);
  }

  /// Stored language tag or `null` for "follow device".
  String? get storedLanguageTag => value?.languageCode;

  bool get isSwahili => (value?.languageCode ?? kDefaultLanguageTag) == 'sw';

  /// Effective locale, resolving "system" against the device.
  Locale? resolve(BuildContext context) {
    final explicit = value;
    if (explicit != null) return explicit;
    final device = Localizations.maybeLocaleOf(context);
    final code = device?.languageCode;
    return tagToLocale(isSupportedLanguageTag(code) ? code : kDefaultLanguageTag);
  }

  Future<void> setLanguage(String? tag) async {
    if (tag != null && !isSupportedLanguageTag(tag)) {
      tag = null;
    }
    final next = tag == null ? null : tagToLocale(tag);
    if (next == value) return;
    value = next;
    await _prefs.setLanguageTag(tag);
  }

  Future<void> followDevice() => setLanguage(null);
}

/// Inherited access to the app [LocaleController].
class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    super.key,
    required LocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static LocaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    assert(scope != null, 'No LocaleScope found in widget tree.');
    return scope!.notifier!;
  }

  static LocaleController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocaleScope>()?.notifier;

  /// Current app language without subscribing (for one-shot reads).
  static LocaleController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LocaleScope>()?.notifier;
}

/// Material + app localizations delegates in dependency order.
List<LocalizationsDelegate<dynamic>> materialLocalizationsDelegates(
    LocaleController controller) {
  return [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
}