import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/core/theme/theme_controller.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/login_page.dart';
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
        routes: {LoginPage.routeName: (_) => const LoginPage()},
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

  testWidgets('the ticker band stays visible after scrolling (regression)',
      (tester) async {
    // A tall surface so the page genuinely overflows and the drag scrolls.
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(_repo()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    final offsetBefore = position.pixels;
    final before = tester.getTopLeft(find.byIcon(Icons.campaign_outlined)).dy;

    // Scroll well past the announcement band.
    await tester.drag(scrollable, const Offset(0, -900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // The page genuinely moved under the pinned chrome.
    expect(position.pixels, greaterThan(offsetBefore),
        reason: 'the drag must scroll the public page');
    expect(
      find.byIcon(Icons.campaign_outlined),
      findsOneWidget,
      reason: 'an announcement must remain on screen while the page scrolls',
    );
    final after = tester.getTopLeft(find.byIcon(Icons.campaign_outlined)).dy;
    // The band is pinned: it stays glued just under the app bar (never riding
    // the content off the top of the viewport, and never dropping below its
    // initial pinned slot — an overscrolling viewport may transiently stretch
    // it upward, which is why the comparison is not strict).
    expect(after, greaterThan(0));
    expect(after, lessThanOrEqualTo(before));
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
  testWidgets('the public header keeps SOS one tap away', (tester) async {
    await tester.pumpWidget(_app(_repo()));
    // The page runs a looping carousel, so never pumpAndSettle here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final sos = find.byKey(const ValueKey('public-header-sos'));
    expect(sos, findsOneWidget);

    // `/emergency` is a protected route: an anonymous visitor is handed to
    // the sign-in wall instead of a broken, token-less emergency screen.
    await tester.tap(sos);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoginPage), findsOneWidget);
  });

}