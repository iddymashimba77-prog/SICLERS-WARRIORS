import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/app.dart';
import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/navigation/app_router.dart';
import 'package:sicklers_warriors/core/navigation/not_found_page.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/core/theme/theme_controller.dart';
import 'package:sicklers_warriors/features/auth/data/auth_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/reset_password_page.dart';
import 'package:sicklers_warriors/features/blood_donation/presentation/pages/donor_home_page.dart';
import 'package:sicklers_warriors/features/public/data/content_repository.dart';
import 'package:sicklers_warriors/features/public/presentation/pages/public_home_page.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// Content client that never invents copy — every endpoint answers with an
/// empty envelope so the public page renders its honest empty states.
ContentRepository get _emptyContent => ContentRepository(
      client: MockClient((_) async => _json({'data': {}}, 404)),
    );

/// Bare [MaterialApp] pumps fall back to the Kiswahili-first brand default;
/// auth copy assertions below are English, so pin the EN table.
Widget _enApp({required Widget home, Map<String, WidgetBuilder>? routes}) =>
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizationsDelegate.supportedLocales,
      home: home,
      routes: routes ?? const {},
    );

Widget _publicHome(String language) {
  final locale = LocaleController(AppPreferences.memory())
    ..value = Locale(language);
  return LocaleScope(
    controller: locale,
    child: ThemeScope(
      controller: ThemeController(AppPreferences.memory()),
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: materialLocalizationsDelegates(locale),
        supportedLocales: AppLocalizationsDelegate.supportedLocales,
        home: PublicHomePage(content: _emptyContent),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('route table (Band 1 correctness)', () {
    testWidgets('pushNamed("/donor-home") resolves to the donor home page',
        (tester) async {
      await tester.pumpWidget(const SicklersWarriorsApp());
      await tester.pumpAndSettle();

      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed(DonorHomePage.routeName);
      await tester.pumpAndSettle();

      // The public home links to this route from three places; before it was
      // registered the push threw instead of rendering a page.
      expect(find.byType(DonorHomePage), findsOneWidget);
      expect(find.text(AppStrings.notSignedIn), findsOneWidget);
    });

    testWidgets('an unknown named route degrades to the not-found page',
        (tester) async {
      await tester.pumpWidget(const SicklersWarriorsApp());
      await tester.pumpAndSettle();

      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed('/no-such-route');
      await tester.pumpAndSettle();

      expect(find.byType(NotFoundPage), findsOneWidget);
      expect(find.text('/no-such-route'), findsOneWidget,
          reason: 'the failed route is surfaced for support/debugging');
      expect(find.widgetWithText(FilledButton, 'Go to home'), findsOneWidget);
    });

    test('the session wall guards the real shell route, not a phantom', () {
      expect(isProtectedRoute('/shell'), isTrue);
      expect(isProtectedRoute('/main-shell'), isFalse,
          reason: "no class declares '/main-shell'; MainShell uses '/shell'");
      expect(isProtectedRoute('/donor-home'), isTrue);
    });
  });

  group('password reset flow (Band 1 correctness)', () {
    testWidgets('without a token the page asks for the reset code',
        (tester) async {
      await tester.pumpWidget(_enApp(home: const ResetPasswordPage()));
      await tester.pump();

      expect(find.text('Reset code'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Reset Password'), findsOneWidget);
    });

    testWidgets('with a token the code field is not asked for',
        (tester) async {
      await tester.pumpWidget(
        _enApp(home: const ResetPasswordPage(token: 'pre-filled')),
      );
      await tester.pump();

      expect(find.text('Reset code'), findsNothing);
    });

    testWidgets('the typed code is sent to the confirm endpoint',
        (tester) async {
      String? sentToken;
      final repo = AuthRepository(
        tokenStore: EphemeralTokenStore(),
        client: MockClient((request) async {
          expect(request.url.path, '/api/auth/password-reset/confirm/');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentToken = body['token'] as String?;
          expect(body['new_password'], 'Str0ngPass1!');
          return _json({'data': {}});
        }),
      );

      await tester.pumpWidget(_enApp(home: ResetPasswordPage(repository: repo)));
      await tester.pump();

      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(3));
      await tester.enterText(fields.at(0), '123456');
      await tester.enterText(fields.at(1), 'Str0ngPass1!');
      await tester.enterText(fields.at(2), 'Str0ngPass1!');
      await tester.tap(find.widgetWithText(FilledButton, 'Reset Password'));
      await tester.pumpAndSettle();

      expect(sentToken, '123456');
      expect(find.text('Password Reset Successful'), findsOneWidget);
    });

    testWidgets('the forgot-password confirmation leads to the code step',
        (tester) async {
      final repo = AuthRepository(
        tokenStore: EphemeralTokenStore(),
        client: MockClient((request) async {
          expect(request.url.path, '/api/auth/password-reset/request/');
          return _json(const {}, 202);
        }),
      );

      await tester.pumpWidget(
        _enApp(
          home: ForgotPasswordPage(repository: repo),
          routes: {
            ResetPasswordPage.routeName: (_) =>
                const ResetPasswordPage(token: ''),
          },
        ),
      );
      await tester.pump();

      await tester.enterText(
          find.byType(TextFormField), 'warrior@example.com');
      await tester.tap(find.widgetWithText(FilledButton, 'Send Reset Code'));
      await tester.pumpAndSettle();

      // The flow used to dead-end here: no way to hand the code back.
      final enterCode = find.widgetWithText(FilledButton, 'Enter Reset Code');
      expect(enterCode, findsOneWidget);

      await tester.tap(enterCode);
      await tester.pumpAndSettle();
      expect(find.byType(ResetPasswordPage), findsOneWidget);
      expect(find.text('Reset code'), findsOneWidget);
    });
  });

  group('public home footer localizes (Band 1 correctness)', () {
    testWidgets('English footer labels resolve from the EN table',
        (tester) async {
      await tester.pumpWidget(_publicHome('en'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Terms'), findsOneWidget);
      expect(find.text('Consent'), findsOneWidget);
      expect(find.text('Contact'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Kiswahili footer labels resolve from the SW table',
        (tester) async {
      await tester.pumpWidget(_publicHome('sw'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Privacy'), findsNothing,
          reason: 'the footer must not stay English under the SW locale');
      expect(find.text('Usiri'), findsOneWidget);
      expect(find.text('Masharti'), findsOneWidget);
      expect(find.text('Idhini'), findsOneWidget);
      expect(find.text('Wasiliana'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
