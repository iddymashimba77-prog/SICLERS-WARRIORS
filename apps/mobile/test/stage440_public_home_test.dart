import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/core/theme/theme_controller.dart';
import 'package:sicklers_warriors/features/public/data/content_repository.dart';
import 'package:sicklers_warriors/features/public/presentation/pages/public_home_page.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

final _articleA = {
  'uid': 'a' * 32,
  'title': 'Article Alpha',
  'category': 'HEALTH',
  'category_label': 'Health',
  'excerpt': 'Alpha excerpt',
  'featured': false,
  'published_at': '2026-09-27T12:00:00Z',
  'author': {'display_name': 'Member'},
};

final _articleB = {
  'uid': 'b' * 32,
  'title': 'Article Bravo',
  'category': 'HEALTH',
  'category_label': 'Health',
  'excerpt': 'Bravo excerpt',
  'featured': true,
  'published_at': '2026-09-27T11:00:00Z',
  'author': {'display_name': 'Editor'},
};

ContentRepository _repo({bool tickerStatic = true}) {
  final client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/news/latest/')) {
      return _json({'data': {'article': _articleA}});
    }
    if (path.endsWith('/news/') &&
        request.url.queryParameters['featured'] == 'true') {
      return _json({
        'data': {
          'count': 1,
          'next': null,
          'results': [_articleB],
        },
      });
    }
    if (path.endsWith('/news/')) {
      return _json({
        'data': {
          'count': 2,
          'next': null,
          'results': [_articleA, _articleB],
        },
      });
    }
    if (path.endsWith('/ticker/')) {
      final msg = tickerStatic ? 'damu salama' : List.filled(120, 'x').join();
      return _json({
        'data': [
          {'message': msg, 'announcement_type': 'BLOOD', 'link_url': ''},
        ],
      });
    }
    return _json({'data': {}}, 404);
  });
  return ContentRepository(client: client);
}

Widget _app(ContentRepository content,
    {ThemeController? theme, LocaleController? locale}) {
  final themeController = theme ?? ThemeController(AppPreferences.memory());
  final localeController =
      locale ?? LocaleController(AppPreferences.memory());
  return LocaleScope(
    controller: localeController,
    child: ThemeScope(
      controller: themeController,
      child: MaterialApp(
        localizationsDelegates: materialLocalizationsDelegates(localeController),
        supportedLocales: AppLocalizationsDelegate.supportedLocales,
        theme: ThemeData(useMaterial3: true),
        home: PublicHomePage(content: content),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ticker band shows the active announcement message', (tester) async {
    await tester.pumpWidget(_app(_repo()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('damu salama'), findsWidgets);
    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    // Short messages crawl too — the band is never static.
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('long ticker message renders as a scrolling marquee', (tester) async {
    await tester.pumpWidget(_app(_repo(tickerStatic: false)));
    await tester.pump();
    await tester.pump();
    final long = List.filled(120, 'x').join();
    expect(find.text(long), findsNWidgets(2));
    // No static ellipsis view; the marquee is animating.
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('news slides render and autoplay advances the carousel', (tester) async {
    await tester.pumpWidget(_app(_repo()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('carousel-dot-active-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('carousel-dot-inactive-1')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 5100));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.byKey(const ValueKey('carousel-dot-active-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('carousel-dot-active-0')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('public theme toggle flips to dark mode', (tester) async {
    final theme = ThemeController(AppPreferences.memory());
    await tester.pumpWidget(_app(_repo(), theme: theme));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('public-theme-toggle')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('public-theme-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(theme.value, ThemeMode.dark);
    expect(
      find.byKey(const ValueKey('public-theme-toggle')),
      findsOneWidget,
    );
  });

  testWidgets('public language toggle switches EN to SW', (tester) async {
    final locale = LocaleController(AppPreferences.memory());
    await tester.pumpWidget(_app(_repo(), locale: locale));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('public-language-toggle')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('public-language-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(locale.storedLanguageTag, 'sw');
    expect(locale.isSwahili, isTrue);
  });
}