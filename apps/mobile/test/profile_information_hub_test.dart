import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/core/theme/theme_controller.dart';
import 'package:sicklers_warriors/features/auth/data/auth_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sicklers_warriors/features/profile/data/profile_repository.dart';
import 'package:sicklers_warriors/features/profile/presentation/pages/profile_page.dart';
import 'package:sicklers_warriors/features/profile/presentation/widgets/profile_information_hub.dart';
import 'package:sicklers_warriors/features/public/presentation/pages/about_pages.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Future<(AuthController, ProfileRepository)> _authenticated() async {
  final store = EphemeralTokenStore();
  await store.writeAccess('access-1');
  await store.writeRefresh('refresh-1');
  final client = MockClient((request) async {
    if (request.url.path == '/api/auth/me/') {
      return _json({
        'data': {
          'email': 'warrior@example.com',
          'first_name': 'Amina',
          'last_name': 'Mwaka',
          'account_status': 'ACTIVE',
          'role_codes': ['PATIENT'],
        },
      });
    }
    if (request.url.path == '/patients/me/') {
      return _json({
        'data': {'notes': ''},
      });
    }
    return _json({'data': <String, dynamic>{}});
  });
  final controller = AuthController(
    repository: AuthRepository(tokenStore: store, client: client),
  );
  await controller.restoreSession();
  return (controller, ProfileRepository(tokenStore: store, client: client));
}

Widget _app({
  required AuthController controller,
  required ProfileRepository repository,
  Locale locale = const Locale('en'),
  ThemeMode mode = ThemeMode.light,
}) {
  final localeController = LocaleController(AppPreferences.memory())
    ..value = locale;
  final themeController = ThemeController(AppPreferences.memory());
  return LocaleScope(
    controller: localeController,
    child: ThemeScope(
      controller: themeController,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: materialLocalizationsDelegates(
          localeController,
        ),
        supportedLocales: AppLocalizationsDelegate.supportedLocales,
        theme: ThemeData(useMaterial3: true),
        darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        themeMode: mode,
        home: ProfilePage(authController: controller, repository: repository),
      ),
    ),
  );
}

Future<void> _tallViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(600, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the information hub sits at the bottom of Profile with every '
      'relocated item', (tester) async {
    await _tallViewport(tester);
    final (controller, repository) = await _authenticated();
    await tester.pumpWidget(
      _app(controller: controller, repository: repository),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-info-hub')), findsOneWidget);
    expect(find.text('About & Information'), findsOneWidget);
    expect(find.text('ABOUT SICKLER\'S WARRIORS'), findsOneWidget);
    expect(find.text('SUPPORT & CONTACT'), findsOneWidget);

    for (final title in const [
      'About Sickler\'s Warriors',
      'Our Mission',
      'How It Works',
      'Team & Partners',
      'Contact Us',
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'missing: $title');
    }

    // The hub is the final content block on the page.
    final hubBottom = tester.getBottomLeft(
      find.byKey(const Key('profile-info-hub')),
    );
    final signOutBottom = tester.getBottomLeft(
      find.widgetWithText(OutlinedButton, 'Sign out'),
    );
    expect(hubBottom.dy, greaterThan(signOutBottom.dy));
  });

  testWidgets('every relocated item opens its existing About page', (
    tester,
  ) async {
    await _tallViewport(tester);
    final (controller, repository) = await _authenticated();
    await tester.pumpWidget(
      _app(controller: controller, repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('About Sickler\'s Warriors'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutWarriorsPage), findsOneWidget);
    expect(
      find.text('More Than Support. A Community of Strength.'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Contact Us'));
    await tester.pumpAndSettle();
    expect(find.byType(ContactUsPage), findsOneWidget);
    expect(find.text('We\'re Here to Connect.'), findsOneWidget);
  });

  testWidgets('the hub is localized in Kiswahili', (tester) async {
    await _tallViewport(tester);
    final (controller, repository) = await _authenticated();
    await tester.pumpWidget(
      _app(
        controller: controller,
        repository: repository,
        locale: const Locale('sw'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kuhusu na Taarifa'), findsOneWidget);
    expect(find.text('KUHUSU SICKLER\'S WARRIORS'), findsOneWidget);
    expect(find.text('MSAADA NA MAWASILIANO'), findsOneWidget);
    expect(find.text('Kuhusu Sickler\'s Warriors'), findsOneWidget);

    await tester.tap(find.text('Kuhusu Sickler\'s Warriors'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutWarriorsPage), findsOneWidget);
    expect(find.text('Zaidi ya Msaada. Jamii ya Nguvu.'), findsOneWidget);
  });

  testWidgets('the hub renders cleanly in dark mode', (tester) async {
    await _tallViewport(tester);
    final (controller, repository) = await _authenticated();
    await tester.pumpWidget(
      _app(
        controller: controller,
        repository: repository,
        mode: ThemeMode.dark,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-info-hub')), findsOneWidget);
    expect(find.text('About & Information'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the hub fits a 320px phone in light and dark mode',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizationsDelegate.supportedLocales,
          theme: ThemeData(useMaterial3: true),
          darkTheme:
              ThemeData(useMaterial3: true, brightness: Brightness.dark),
          themeMode: mode,
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: ProfileInformationHub(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile-info-hub')), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'hub overflowed at 320px in $mode',
      );
    }
  });
}
