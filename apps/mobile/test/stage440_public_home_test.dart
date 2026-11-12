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
  final localeController = locale ?? LocaleController(AppPreferences.memory());
  return LocaleScope(
    controller: localeController,
    child: ThemeScope(
      controller: themeController,
      child: ListenableBuilder(
        listenable: localeController,
        builder: (context, _) => MaterialApp(
          locale: localeController.value,
          localizationsDelegates: materialLocalizationsDelegates(
            localeController,
          ),
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
    ),
  );
}

Future<void> _pumpAt(
  WidgetTester tester,
  Size size, {
  ThemeController? theme,
  LocaleController? locale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(_app(theme: theme, locale: locale));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the reference hero without the removed sections', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _pumpAt(tester, const Size(390, 1600));

    expect(find.text('SICKLE'), findsOneWidget);
    expect(find.text('CELL'), findsOneWidget);
    expect(find.text('WARRIORS'), findsOneWidget);
    expect(find.text('Empowering Every Warrior.'), findsOneWidget);
    expect(
      find.text('Connecting Care, Community and Hope.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-cta-join')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-cta-login')), findsOneWidget);

    for (final removed in [
      'Complete care, one platform',
      'Everything a Warrior Needs',
      'Seven connected corners of care, support and community.',
      'Explore All Services',
      'A clearer path from first tap to lasting care',
      'Built for the real life of a Warrior',
      'Trust, Privacy & Consent',
      'Ready to Join Our Community?',
      'Latest News',
      'Read the latest updates',
      'Patient-first by design',
    ]) {
      expect(find.text(removed), findsNothing, reason: removed);
    }
  });

  testWidgets('the header keeps only SOS, theme and language', (tester) async {
    addTearDown(tester.view.reset);
    await _pumpAt(tester, const Size(390, 1600));

    final topBar = find.byKey(const ValueKey('public-top-bar'));
    expect(topBar, findsOneWidget);
    for (final key in [
      'public-header-sos',
      'public-theme-toggle',
      'public-language-toggle',
    ]) {
      expect(
        find.descendant(of: topBar, matching: find.byKey(ValueKey(key))),
        findsOneWidget,
        reason: key,
      );
    }
    expect(
      find.descendant(of: topBar, matching: find.byIcon(Icons.menu)),
      findsNothing,
    );
    expect(
      find.descendant(of: topBar, matching: find.byType(AppLogo)),
      findsNothing,
    );
    expect(
      find.descendant(of: topBar, matching: find.byType(AppBrand)),
      findsNothing,
    );
    expect(
      find.descendant(of: topBar, matching: find.text('Login')),
      findsNothing,
    );
    expect(
      find.descendant(of: topBar, matching: find.text('Sign up')),
      findsNothing,
    );
  });

  testWidgets('the public home defaults to dark and the toggle switches', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final theme = ThemeController(AppPreferences.memory());
    await _pumpAt(tester, const Size(390, 1600), theme: theme);

    expect(theme.value, ThemeMode.system);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('public-theme-toggle')));
    await tester.pump();
    expect(theme.value, ThemeMode.light);
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('public-theme-toggle')));
    await tester.pump();
    expect(theme.value, ThemeMode.dark);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
  });

  testWidgets('the language toggle switches EN to SW', (tester) async {
    addTearDown(tester.view.reset);
    final locale = LocaleController(AppPreferences.memory());
    await _pumpAt(tester, const Size(390, 1800), locale: locale);

    expect(find.text('Join the community'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('public-language-toggle')));
    await tester.pumpAndSettle();

    expect(locale.isSwahili, isTrue);
    expect(find.text('Jiunge na jamii'), findsOneWidget);
    expect(find.text('Kifuatiliaji cha Unyevu'), findsOneWidget);
    expect(find.text('SW'), findsOneWidget);
  });

  testWidgets('join opens registration', (tester) async {
    addTearDown(tester.view.reset);
    await _pumpAt(tester, const Size(390, 1600));

    await tester.tap(find.byKey(const ValueKey('home-cta-join')));
    await tester.pumpAndSettle();
    expect(find.text('signup-route'), findsOneWidget);
  });

  testWidgets('login opens the sign-in page', (tester) async {
    addTearDown(tester.view.reset);
    await _pumpAt(tester, const Size(390, 1600));

    await tester.tap(find.byKey(const ValueKey('home-cta-login')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('the glass menu exposes six service tiles and a donate row', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _pumpAt(tester, const Size(390, 1800));

    for (final id in [
      'health',
      'hydration',
      'blood',
      'education',
      'community',
      'ai',
    ]) {
      expect(
        find.byKey(ValueKey('home-service-$id')),
        findsOneWidget,
        reason: id,
      );
    }
    expect(find.byKey(const ValueKey('home-service-donate')), findsNothing);
    expect(find.byKey(const ValueKey('home-donate')), findsOneWidget);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-service-health')),
        matching: find.text('Health Management'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-service-community')),
        matching: find.text('Community'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-service-community')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );

    final heights = [
      for (final id in [
        'health',
        'hydration',
        'blood',
        'education',
        'community',
        'ai',
      ])
        tester.getSize(find.byKey(ValueKey('home-service-$id'))).height,
    ];
    expect(heights.toSet().length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('education opens the public academy', (tester) async {
    addTearDown(tester.view.reset);
    await _pumpAt(tester, const Size(390, 1800));

    await tester.tap(find.byKey(const ValueKey('home-service-education')));
    await tester.pumpAndSettle();
    expect(find.text('education-route'), findsOneWidget);
  });

  testWidgets('protected shortcuts route anonymous visitors to login', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    for (final id in ['health', 'hydration', 'blood', 'community', 'ai']) {
      await tester.pumpWidget(const SizedBox());
      await _pumpAt(tester, const Size(390, 1800));
      await tester.tap(find.byKey(ValueKey('home-service-$id')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget, reason: id);
    }

    await tester.pumpWidget(const SizedBox());
    await _pumpAt(tester, const Size(390, 1800));
    await tester.tap(find.byKey(const ValueKey('home-donate')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('the phone mockup keeps its existing internal screen', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _pumpAt(tester, const Size(390, 1800));

    final phone = find.byKey(const ValueKey('hero-phone'));
    expect(phone, findsOneWidget);
    expect(tester.getSize(phone).height, 360);
    expect(find.byKey(const ValueKey('hero-phone-tilt')), findsOneWidget);

    for (final label in [
      'Quick actions',
      'Doctor Connection',
      'Emergency Support',
      'Education — Warrior Academy',
      'Donate & Support',
      'Emergency & SOS',
    ]) {
      expect(
        find.descendant(of: phone, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
  });

  testWidgets('stays laid out across phone, tablet and desktop widths', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    for (final width in [
      320.0,
      360.0,
      390.0,
      430.0,
      768.0,
      1024.0,
      1440.0,
    ]) {
      await _pumpAt(tester, Size(width, 1600));

      expect(
        find.byKey(const ValueKey('public-hero')),
        findsOneWidget,
        reason: 'hero at ${width}px',
      );
      expect(
        find.byKey(const ValueKey('hero-services')),
        findsOneWidget,
        reason: 'services at ${width}px',
      );
      expect(
        find.byKey(const ValueKey('hero-phone')),
        findsOneWidget,
        reason: 'phone at ${width}px',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at ${width}px',
      );
    }
  });

  testWidgets('the light theme keeps the same layout', (tester) async {
    addTearDown(tester.view.reset);
    final theme = ThemeController(AppPreferences.memory())
      ..value = ThemeMode.light;
    await _pumpAt(tester, const Size(390, 1800), theme: theme);

    expect(find.text('SICKLE'), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('hero-services')), findsOneWidget);
    expect(find.byKey(const ValueKey('hero-phone')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SOS keeps the emergency path one tap away', (tester) async {
    addTearDown(tester.view.reset);
    await _pumpAt(tester, const Size(390, 1600));

    await tester.tap(find.byKey(const ValueKey('public-header-sos')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });
}
