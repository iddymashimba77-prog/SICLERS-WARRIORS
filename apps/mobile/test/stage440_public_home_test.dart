import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/core/theme/theme_controller.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/login_page.dart';
import 'package:sicklers_warriors/features/public/presentation/pages/public_home_page.dart';
import 'package:sicklers_warriors/shared/widgets/app_logo.dart';

Widget _app({ThemeController? theme, LocaleController? locale}) {
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
        home: const PublicHomePage(),
        routes: {
          LoginPage.routeName: (_) => const LoginPage(),
          '/signup': (_) => const Scaffold(body: Text('signup-route')),
          '/education': (_) => const Scaffold(body: Text('education-route')),
        },
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the public home without the mission care journey',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Empowering Every Warrior.'), findsOneWidget);
    expect(
      find.text('A clearer path from first tap to lasting care'),
      findsNothing,
    );
    expect(find.text('Today\'s entries'), findsNothing);
    expect(find.text('Latest News'), findsNothing);
    expect(find.text('Read the latest updates'), findsNothing);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
    expect(find.text('Read the latest updates'), findsNothing);
  });

  testWidgets('the hero is cleaned of the slogan, intro and proof lines',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Care, community and courage'), findsNothing);
    expect(find.textContaining('A digital health, blood and support'),
        findsNothing);
    expect(find.text('Patient-first by design'), findsNothing);
    expect(find.text('Consent-led health data'), findsNothing);
    expect(find.text('Care that stays connected'), findsNothing);
  });

  testWidgets('the header no longer shows the top-left brand lockup',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final header = find.byType(SliverAppBar);
    expect(header, findsOneWidget);
    expect(
      find.descendant(of: header, matching: find.byType(AppBrand)),
      findsNothing,
    );
    expect(
      find.descendant(of: header, matching: find.byType(AppLogo)),
      findsNothing,
    );
  });

  testWidgets('public theme toggle flips to dark mode', (tester) async {
    final theme = ThemeController(AppPreferences.memory());
    await tester.pumpWidget(_app(theme: theme));
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
    await tester.pumpWidget(_app(locale: locale));
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

  testWidgets('the redesigned home stays laid out across phone widths',
      (tester) async {
    for (final width in [320.0, 360.0, 375.0, 390.0, 430.0]) {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Empowering Every Warrior.'),
        findsOneWidget,
        reason: 'hero missing at ${width}px',
      );
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
    }
  });

  testWidgets('the desktop header keeps only SOS, theme and language',
      (tester) async {
    for (final width in [1025.0, 1280.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final header = find.byType(SliverAppBar);
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('public-header-sos')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('public-theme-toggle')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('public-language-toggle')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('mega-About')), findsNothing);
      expect(
        find.descendant(of: header, matching: find.text('Login')),
        findsNothing,
      );
      expect(
        find.descendant(of: header, matching: find.text('Sign up')),
        findsNothing,
      );
    }
  });

  testWidgets('the mobile header keeps only SOS, theme and language',
      (tester) async {
    for (final width in [320.0, 390.0, 430.0, 719.0]) {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final header = find.byType(SliverAppBar);
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('public-header-sos')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('public-theme-toggle')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('public-language-toggle')),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.menu), findsNothing);
      expect(
        find.descendant(of: header, matching: find.text('Login')),
        findsNothing,
      );
    }
  });

  testWidgets('the hero integrates the phone and leaves no lower section',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));

    expect(find.text('Complete care, one platform'), findsNothing);
    expect(find.text('Everything a Warrior Needs'), findsNothing);
    expect(
      find.text('Seven connected corners of care, support and community.'),
      findsNothing,
    );
    expect(find.text('Explore All Services'), findsNothing);
    expect(
      find.byKey(const ValueKey('phone-showcase-section')),
      findsNothing,
    );

    final hero = find.byKey(const ValueKey('public-hero'));
    expect(hero, findsOneWidget);
    expect(find.byType(SliverToBoxAdapter), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SliverToBoxAdapter),
        matching: hero,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hero,
        matching: find.byKey(const ValueKey('hero-phone')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hero,
        matching: find.byKey(const ValueKey('hero-services')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hero,
        matching: find.byKey(const ValueKey('hero-logo')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the integrated phone keeps its original internal screen',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));

    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Doctor Connection'), findsOneWidget);
    expect(find.text('Emergency Support'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Education — Warrior Academy'), findsOneWidget);
    expect(find.text('Hydration Tracker'), findsOneWidget);
    expect(find.text('Ask AI'), findsOneWidget);
  });

  testWidgets('the hero shows the brand, headline and premium actions',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));

    expect(find.text('Empowering Every Warrior.'), findsOneWidget);
    expect(
      find.text('Connecting Care, Community and Hope.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-cta-join')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-cta-login')), findsOneWidget);
    expect(find.text('Join the Community'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('the glass panel exposes the seven public service shortcuts',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));

    for (final id in [
      'health',
      'hydration',
      'blood',
      'education',
      'community',
      'ai',
      'donate',
    ]) {
      expect(
        find.byKey(ValueKey('home-service-$id')),
        findsOneWidget,
        reason: 'missing $id service card',
      );
    }
    expect(find.text('Care services'), findsOneWidget);
    expect(find.text('Hydration Tracker'), findsOneWidget);
    expect(find.text('Community Forum'), findsOneWidget);
    expect(find.text('Ask AI'), findsOneWidget);
    expect(find.textContaining('Admin'), findsNothing);
    final cardSizes = [
      for (final id in [
        'health',
        'hydration',
        'blood',
        'education',
        'community',
        'ai',
        'donate',
      ])
        tester.getSize(find.byKey(ValueKey('home-service-$id'))),
    ];
    expect(
      cardSizes.every((size) => size.height == cardSizes.first.height),
      isTrue,
      reason: 'service cards should share one height',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('education shortcut opens the public academy',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));

    await tester.tap(find.byKey(const ValueKey('home-service-education')));
    await tester.pumpAndSettle();
    expect(find.text('education-route'), findsOneWidget);
  });

  testWidgets('the phone mockup stays interactive inside the hero',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));

    await tester.tap(find.text('Emergency Support'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('protected shortcuts route anonymous visitors to login',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));

    await tester.tap(find.byKey(const ValueKey('home-service-health')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('the hero stays balanced on tablet and desktop widths',
      (tester) async {
    for (final size in [
      const Size(768, 1600),
      const Size(1024, 1600),
      const Size(1280, 1600),
      const Size(1440, 1600),
      const Size(1920, 1600),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));

      expect(
        find.byKey(const ValueKey('public-hero')),
        findsOneWidget,
        reason: 'hero missing at ${size.width}px',
      );
      expect(
        find.byKey(const ValueKey('hero-phone')),
        findsOneWidget,
        reason: 'phone missing at ${size.width}px',
      );
      expect(
        find.byKey(const ValueKey('hero-services')),
        findsOneWidget,
        reason: 'services missing at ${size.width}px',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at ${size.width}px',
      );
    }
  });

  testWidgets('the public header keeps SOS one tap away', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final sos = find.byKey(const ValueKey('public-header-sos'));
    expect(sos, findsOneWidget);

    await tester.tap(sos);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoginPage), findsOneWidget);
  });
}
