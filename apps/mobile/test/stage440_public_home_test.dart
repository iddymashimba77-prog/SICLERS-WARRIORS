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
        routes: {LoginPage.routeName: (_) => const LoginPage()},
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

  testWidgets('the Complete Care section is gone and the phone ends the page',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Complete care, one platform'), findsNothing);
    expect(find.text('Everything a Warrior Needs'), findsNothing);
    expect(
      find.text('Seven connected corners of care, support and community.'),
      findsNothing,
    );
    expect(find.text('Explore All Services'), findsNothing);

    final phone = find.byKey(const ValueKey('phone-showcase-section'));
    expect(phone, findsOneWidget);
    expect(find.text('Quick actions'), findsOneWidget);

    final column = tester.widget<Column>(
      find
          .descendant(
            of: find.byType(SliverToBoxAdapter),
            matching: find.byType(Column),
          )
          .first,
    );
    expect(column.children.last.key, const ValueKey('phone-showcase-section'));
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
