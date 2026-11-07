import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/core/theme/app_theme.dart';
import 'package:sicklers_warriors/core/theme/theme_controller.dart';
import 'package:sicklers_warriors/features/auth/data/auth_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sicklers_warriors/features/education/data/education_repository.dart';
import 'package:sicklers_warriors/features/education/presentation/pages/education_page.dart';
import 'package:sicklers_warriors/features/public/data/content_repository.dart';
import 'package:sicklers_warriors/features/public/presentation/pages/public_home_page.dart';
import 'package:sicklers_warriors/shared/widgets/banners/animated_page_banner.dart';
import 'package:sicklers_warriors/shared/widgets/banners/healthcare_banner_art.dart';
import 'package:sicklers_warriors/shared/widgets/banners/page_banner_catalog.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Widget _app(
  Widget child, {
  ThemeData? theme,
  Locale locale = const Locale('en'),
  bool reduceMotion = false,
}) => MaterialApp(
  locale: locale,
  theme: theme ?? AppTheme.light,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizationsDelegate.supportedLocales,
  builder: reduceMotion
      ? (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        )
      : null,
  home: Scaffold(body: child),
);

AnimatedPageBanner _banner({
  BannerScene scene = BannerScene.careTeam,
  bool animate = true,
}) => AnimatedPageBanner(
  title: 'Your Health, Our Priority',
  description: 'Your journey matters.',
  scene: scene,
  semanticsLabel: 'A diverse African healthcare team.',
  margin: EdgeInsets.zero,
  animate: animate,
);

Future<void> _size(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<AuthController> _auth({required bool signedIn}) async {
  final store = EphemeralTokenStore();
  if (signedIn) {
    await store.writeAccess('access-1');
    await store.writeRefresh('refresh-1');
  }
  final controller = AuthController(
    repository: AuthRepository(
      tokenStore: store,
      client: MockClient(
        (request) async => _json({
          'data': {
            'email': 'warrior@example.com',
            'first_name': 'Amina',
            'last_name': 'Mwaka',
            'account_status': 'ACTIVE',
            'role_codes': ['PATIENT'],
          },
        }),
      ),
    ),
  );
  addTearDown(controller.dispose);
  await controller.restoreSession();
  return controller;
}

EducationRepository _educationRepo() => EducationRepository(
  tokenStore: EphemeralTokenStore(),
  client: MockClient((request) async {
    if (request.url.path.endsWith('/education/categories/')) {
      return _json({
        'data': {'results': <Object>[]},
      });
    }
    if (request.url.path.endsWith('/education/content/')) {
      return _json({
        'data': {'results': <Object>[]},
      });
    }
    return _json({'data': <String, Object>{}});
  }),
);

Widget _publicApp(ContentRepository content) {
  final themeController = ThemeController(AppPreferences.memory());
  final localeController = LocaleController(AppPreferences.memory());
  return LocaleScope(
    controller: localeController,
    child: ThemeScope(
      controller: themeController,
      child: MaterialApp(
        localizationsDelegates: materialLocalizationsDelegates(
          localeController,
        ),
        supportedLocales: AppLocalizationsDelegate.supportedLocales,
        theme: ThemeData(useMaterial3: true),
        home: PublicHomePage(content: content),
      ),
    ),
  );
}

ContentRepository _publicRepo() => ContentRepository(
  client: MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/news/latest/')) {
      return _json({
        'data': {'article': null},
      });
    }
    if (path.endsWith('/news/')) {
      return _json({
        'data': {'count': 0, 'next': null, 'results': <Object>[]},
      });
    }
    if (path.endsWith('/ticker/')) {
      return _json({'data': <Object>[]});
    }
    return _json({'data': <String, Object>{}}, 404);
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the catalogue covers every requested authenticated surface', () {
    expect(bannerPageCatalog.length, BannerPage.values.length);
    expect(BannerPage.values.length, 9);
    expect(
      bannerPageCatalog.values.map((spec) => spec.scene).toSet().length,
      9,
    );
  });

  testWidgets('renders copy, illustration and its accessibility description', (
    tester,
  ) async {
    await _size(tester, const Size(390, 800));
    await tester.pumpWidget(_app(_banner()));
    await tester.pump();

    expect(find.text('Your Health, Our Priority'), findsOneWidget);
    expect(find.text('Your journey matters.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('banner-art-animated')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.image == true &&
            widget.properties.label == 'A diverse African healthcare team.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('uses a static fallback when motion is disabled', (tester) async {
    await _size(tester, const Size(390, 800));
    await tester.pumpWidget(_app(_banner(animate: false)));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('banner-art-static')),
      findsOneWidget,
    );
  });

  testWidgets('honours the platform reduced-motion setting', (tester) async {
    await _size(tester, const Size(390, 800));
    await tester.pumpWidget(_app(_banner(), reduceMotion: true));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('banner-art-static')),
      findsOneWidget,
    );
  });

  testWidgets('scales down on phones and keeps the horizontal composition', (
    tester,
  ) async {
    await _size(tester, const Size(360, 800));
    await tester.pumpWidget(_app(_banner(animate: false)));
    await tester.pump();
    expect(tester.getSize(find.byType(AnimatedPageBanner)).height, 136);

    await _size(tester, const Size(1200, 900));
    await tester.pumpWidget(_app(_banner(animate: false)));
    await tester.pump();
    expect(tester.getSize(find.byType(AnimatedPageBanner)).height, 154);
  });

  testWidgets('renders in light and dark themes', (tester) async {
    await _size(tester, const Size(900, 700));
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(_app(_banner(animate: false), theme: theme));
      await tester.pump();
      expect(find.text('Your Health, Our Priority'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('every scene paints without layout or paint errors', (
    tester,
  ) async {
    await _size(tester, const Size(900, 700));
    for (final scene in BannerScene.values) {
      await tester.pumpWidget(_app(_banner(scene: scene, animate: false)));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: scene.name);
    }
  });

  testWidgets('Kiswahili resolves through the catalogue', (tester) async {
    await _size(tester, const Size(900, 700));
    await tester.pumpWidget(
      _app(
        const PageBanner(page: BannerPage.dashboard, margin: EdgeInsets.zero),
        locale: const Locale('sw'),
      ),
    );
    await tester.pump();

    expect(find.text('Afya Yako, Kipaumbele Chetu'), findsOneWidget);
    expect(
      find.text('Safari yako ni muhimu. Tuko hapa kukuunga mkono kila hatua.'),
      findsOneWidget,
    );
  });

  testWidgets('never appears on a signed-out protected page', (tester) async {
    await _size(tester, const Size(900, 1600));
    await tester.pumpWidget(
      _app(
        EducationPage(
          authController: await _auth(signedIn: false),
          repository: _educationRepo(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PageBanner), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('appears on the authenticated education surface', (tester) async {
    await _size(tester, const Size(900, 1600));
    await tester.pumpWidget(
      _app(
        EducationPage(
          authController: await _auth(signedIn: true),
          repository: _educationRepo(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PageBanner), findsOneWidget);
    expect(find.text('Knowledge Empowers Your Health'), findsOneWidget);
  });

  testWidgets('the public home page remains banner-free', (tester) async {
    await _size(tester, const Size(900, 1400));
    await tester.pumpWidget(_publicApp(_publicRepo()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PageBanner), findsNothing);
  });
}
