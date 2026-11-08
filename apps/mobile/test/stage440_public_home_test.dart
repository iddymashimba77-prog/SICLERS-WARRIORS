import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/core/theme/theme_controller.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/login_page.dart';
import 'package:sicklers_warriors/features/public/presentation/pages/public_home_page.dart';

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

  testWidgets('renders the member care journey and not public news',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Empowering Every Warrior.'), findsOneWidget);
    expect(
      find.text('A clearer path from first tap to lasting care'),
      findsOneWidget,
    );
    expect(find.text('Today\'s entries'), findsNothing);
    expect(find.text('Latest News'), findsNothing);
    expect(find.text('Read the latest updates'), findsNothing);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
    expect(find.text('Read the latest updates'), findsNothing);
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
