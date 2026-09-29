import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/core/theme/theme_controller.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/public/presentation/controllers/branding_controller.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StoredThemeMode + conversion helpers', () {
    test('defaults to system', () {
      expect(AppPreferences.memory().storedThemeMode, StoredThemeMode.system);
      expect(storedToFlutter(StoredThemeMode.system), ThemeMode.system);
    });

    test('round-trips between stored and Flutter enums', () {
      for (final mode in StoredThemeMode.values) {
        expect(flutterToStored(storedToFlutter(mode)), mode);
      }
    });

    test('parse tolerates corrupt / unknown raw values', () {
      expect(StoredThemeMode.parse('dark'), StoredThemeMode.dark);
      expect(StoredThemeMode.parse('purple'), StoredThemeMode.system);
      expect(StoredThemeMode.parse(null), StoredThemeMode.system);
    });
  });

  group('Language tag helpers', () {
    test('supported tags are en/sw only', () {
      expect(isSupportedLanguageTag('en'), isTrue);
      expect(isSupportedLanguageTag('sw'), isTrue);
      expect(isSupportedLanguageTag('fr'), isFalse);
      expect(isSupportedLanguageTag(null), isFalse);
    });

    test('tagToLocale defaults fallback tags; preserves valid ones', () {
      expect(tagToLocale('sw').languageCode, 'sw');
      expect(tagToLocale('en').languageCode, 'en');
      expect(tagToLocale(null).languageCode, 'en');
      expect(tagToLocale('').languageCode, 'en');
    });
  });

  group('ThemeController', () {
    test('defaults to system and persists a new mode', () async {
      final prefs = AppPreferences.memory();
      final controller = ThemeController(prefs);
      expect(controller.value, ThemeMode.system);

      await controller.setMode(ThemeMode.dark);
      expect(controller.value, ThemeMode.dark);
      expect(prefs.storedThemeMode, StoredThemeMode.dark);

      await controller.setMode(ThemeMode.light);
      expect(controller.value, ThemeMode.light);
      expect(prefs.storedThemeMode, StoredThemeMode.light);
    });

    test('no-op mode set does not clobber storage', () async {
      final controller = ThemeController(AppPreferences.memory());
      final before = controller.value;
      await controller.setMode(before);
      expect(controller.value, before);
    });

    test('reload re-seeds from swapped preferences', () async {
      final seeded = AppPreferences.memory();
      await seeded.setThemeMode(StoredThemeMode.light);
      final controller = ThemeController(AppPreferences.memory());
      controller.reload(seeded);
      expect(controller.value, ThemeMode.light);
      expect(controller.storedMode, StoredThemeMode.light);
    });
  });

  group('LocaleController', () {
    test('defaults to follow-device (null value)', () {
      final controller = LocaleController(AppPreferences.memory());
      expect(controller.value, isNull);
    });

    test('setLanguage persists en/sw and clears for an unknown tag', () async {
      final prefs = AppPreferences.memory();
      final controller = LocaleController(prefs);

      await controller.setLanguage('sw');
      expect(controller.value?.languageCode, 'sw');
      expect(controller.isSwahili, isTrue);
      expect(prefs.storedLanguageTag, 'sw');

      await controller.setLanguage('en');
      expect(controller.value?.languageCode, 'en');
      expect(controller.isSwahili, isFalse);

      await controller.setLanguage('tlh');
      // Unsupported tags behave like "follow device" so the app never breaks.
      expect(controller.value, isNull);
      expect(prefs.storedLanguageTag, isNull);
    });

    test('followDevice clears the stored tag', () async {
      final controller = LocaleController(AppPreferences.memory());
      await controller.setLanguage('sw');
      await controller.followDevice();
      expect(controller.value, isNull);
    });

    test('reload re-seeds from the stored tag', () async {
      final seeded = AppPreferences.memory();
      await seeded.setLanguageTag('sw');
      final controller = LocaleController(AppPreferences.memory());
      controller.reload(seeded);
      expect(controller.value?.languageCode, 'sw');
    });
  });

  group('SharedPrefsTokenStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('writes, reads and clears the token pair', () async {
      final store = SharedPrefsTokenStore();
      expect(await store.readAccess(), isNull);
      expect(await store.readRefresh(), isNull);

      await store.writeAccess('access-9');
      await store.writeRefresh('refresh-9');
      expect(await store.readAccess(), 'access-9');
      expect(await store.readRefresh(), 'refresh-9');

      await store.clear();
      expect(await store.readAccess(), isNull);
      expect(await store.readRefresh(), isNull);
    });
  });

  group('BrandingController', () {
    test('parses the live brand payload fields', () {
      final info = BrandingInfo.fromJson({
        'has_logo': true,
        'logo_url': '/api/branding/logo/',
        'logo_alt': 'Sickler\u2019s Warriors',
      });
      expect(info.hasLogo, isTrue);
      expect(info.logoAlt, 'Sickler\u2019s Warriors');
      expect(info.logoUrl, '/api/branding/logo/');
      expect(const BrandingInfo.none().hasLogo, isFalse);
    });

    test('load() ingests the envelope from the network', () async {
      final client = MockClient((request) async => _json({
            'data': {
              'has_logo': true,
              'logo_url': '/api/branding/logo/',
              'logo_alt': 'SW',
            },
          }));
      final controller = BrandingController(client: client);
      await controller.load();
      expect(controller.hasLogo, isTrue);
      expect(controller.info.logoAlt, 'SW');
      expect(controller.resolvedLogoUrl, 'http://localhost:8000/api/branding/logo/');
      controller.dispose();
    });

    test('load() fails silently and keeps the none() fallback', () async {
      final client = MockClient((request) async => _json({
            'error': {'code': 'SERVER_ERROR', 'message': 'boom'},
          }, 500));
      final controller = BrandingController(client: client);
      await controller.load();
      expect(controller.hasLogo, isFalse);
      expect(controller.resolvedLogoUrl, '');
      controller.dispose();
    });
  });

  group('AppLocalizations dictionaries', () {
    test('every key has a non-empty value in both locales', () {
      for (final locale in ['en', 'sw']) {
        final s = AppLocalizations(Locale(locale));
        for (final key in s.keys) {
          final value = s.tr(key);
          expect(value, isNotEmpty,
              reason: '[$locale] "$key" translated to an empty string');
          expect(value, isNot(key),
              reason: '[$locale] tr("$key") fell back to the raw key');
        }
      }
    });

    test('flagship public labels translate as expected', () {
      const en = AppLocalizations(Locale('en'));
      const sw = AppLocalizations(Locale('sw'));
      expect(sw.tr('nav.home'), 'Nyumbani');
      expect(sw.tr('nav.doctor'), 'Daktari');
      expect(sw.tr('nav.treatment'), 'Tiba');
      expect(sw.tr('nav.donate'), 'Changia');
      expect(sw.tr('nav.profile'), 'Wasifu');
      expect(en.tr('nav.home'), 'Home');
      expect(sw.tr('common.signIn'), 'Login');
      expect(en.tr('common.signIn'), 'Login');
    });
  });
}