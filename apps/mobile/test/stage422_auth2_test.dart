import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/features/auth/data/auth_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/domain/auth_types.dart';
import 'package:sicklers_warriors/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/login_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/set_pin_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/signup_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/verification_submission_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/widgets/auth_gate.dart';
import 'package:sicklers_warriors/features/auth/presentation/widgets/session_scope.dart';
import 'package:sicklers_warriors/features/public/presentation/pages/public_home_page.dart';
import 'package:sicklers_warriors/shared/widgets/main_shell.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// App on the English table: a bare [MaterialApp] falls back to the
/// Kiswahili-first brand default, which would flip every copy assertion.
Widget _enApp(Widget home, {Map<String, WidgetBuilder> routes = const {}}) =>
    MaterialApp(
      home: home,
      routes: routes,
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('sw')],
    );

Map<String, dynamic> _loginPayload({
  List<String> roles = const ['PATIENT'],
  String? doctorStatus,
  bool hasLoginPin = true,
  Map<String, dynamic>? facility,
}) =>
    {
      'data': {
        'access': 'access-1',
        'refresh': 'refresh-1',
        'user': {
          'email': 'user@example.com',
          'account_status': 'ACTIVE',
          'role_codes': roles,
          if (doctorStatus != null) 'doctor_verification_status': doctorStatus,
          'is_verified_doctor': doctorStatus == 'APPROVED',
          if (facility != null) 'facility': facility,
          'has_login_pin': hasLoginPin,
        },
      },
    };

http.Response _loginResponse({
  List<String> roles = const ['PATIENT'],
  String? doctorStatus,
  bool hasLoginPin = true,
  Map<String, dynamic>? facility,
}) =>
    _json(_loginPayload(
      roles: roles,
      doctorStatus: doctorStatus,
      hasLoginPin: hasLoginPin,
      facility: facility,
    ));

void main() {
  group('AUTH-2 sign-in surface', () {
    testWidgets('cold start with no session lands on Public Home',
        (tester) async {
      final controller = AuthController(
        repository: AuthRepository(tokenStore: EphemeralTokenStore()),
      );
      await controller.restoreSession();
      await tester.pumpWidget(
        SessionScope(
          controller: controller,
          child: _enApp(const AuthGate()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PublicHomePage), findsOneWidget);
    });

    testWidgets('password sign-in enters the patient shell', (tester) async {
      final store = EphemeralTokenStore();
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/login/');
        return _loginResponse();
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await tester.pumpWidget(
        SessionScope(
          controller: controller,
          child: _enApp(LoginPage(controller: controller), routes: {
            MainShell.routeName: (_) => const MainShell(),
          }),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'user@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'Str0ngPass1!');
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.login));
      await tester.pumpAndSettle();
      expect(controller.isAuthenticated, isTrue);
      expect(find.byType(MainShell), findsOneWidget);
    });

    testWidgets('a remembered identity signs in with the PIN only',
        (tester) async {
      final store = EphemeralTokenStore();
      await store.writeRememberedIdentity('user@example.com');
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/pin/login/');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['email_or_phone'], 'user@example.com');
        expect(body['pin'], '4821');
        return _loginResponse();
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await controller.restoreSession();
      await tester.pumpWidget(
        SessionScope(
          controller: controller,
          child: _enApp(LoginPage(controller: controller), routes: {
            MainShell.routeName: (_) => const MainShell(),
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '4821');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in with PIN'));
      await tester.pumpAndSettle();
      expect(controller.isAuthenticated, isTrue);
      expect(find.byType(MainShell), findsOneWidget);
    });

    testWidgets('first sign-in routes to the PIN-setup step then the shell',
        (tester) async {
      final store = EphemeralTokenStore();
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/login/') {
          return _loginResponse(hasLoginPin: false);
        }
        if (request.url.path == '/api/auth/pin/set/') {
          return http.Response('', 204);
        }
        throw Exception('unexpected ${request.url.path}');
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await tester.pumpWidget(
        SessionScope(
          controller: controller,
          child: _enApp(LoginPage(controller: controller), routes: {
            SetPinPage.routeName: (_) => const SetPinPage(),
            MainShell.routeName: (_) => const MainShell(),
          }),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'user@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'Str0ngPass1!');
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.login));
      await tester.pumpAndSettle();
      expect(find.byType(SetPinPage), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), '4821');
      await tester.enterText(find.byType(TextField).at(1), '4821');
      await tester.tap(find.widgetWithText(FilledButton, 'Save PIN'));
      await tester.pumpAndSettle();
      expect(controller.hasLoginPin, isTrue);
      expect(find.byType(MainShell), findsOneWidget);
    });
  });

  group('Registration flow', () {
    testWidgets('non-professional sign-up opens the PIN-setup step',
        (tester) async {
      final store = EphemeralTokenStore();
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/register/');
        return _json({
          'access': 'new-access',
          'refresh': 'new-refresh',
          'user': {
            'email': 'newbie@example.com',
            'account_status': 'ACTIVE',
            'has_login_pin': false,
          },
          'verification_required': false,
        }, 201);
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await tester.pumpWidget(
        SessionScope(
          controller: controller,
          child: _enApp(const SignupPage(), routes: {
            SetPinPage.routeName: (_) => const SetPinPage(),
            LoginPage.routeName: (_) => const LoginPage(),
          }),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'newbie@example.com');
      await tester.enterText(fields.at(3), 'Str0ngPass9!');
      await tester.enterText(fields.at(4), 'Str0ngPass9!');
      final submit = find.widgetWithText(FilledButton, 'Create Account');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(controller.isAuthenticated, isTrue);
      expect(find.byType(SetPinPage), findsOneWidget);
    });

    testWidgets('professional sign-up opens the document C5 pipeline',
        (tester) async {
      final store = EphemeralTokenStore();
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/register/');
        return _json({
          'access': 'new-access',
          'refresh': 'new-refresh',
          'user': {
            'email': 'doc@example.com',
            'account_status': 'ACTIVE',
            'role_codes': ['DOCTOR'],
            'has_login_pin': false,
          },
          'verification_required': true,
        }, 201);
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await tester.pumpWidget(
        SessionScope(
          controller: controller,
          child: _enApp(const SignupPage(), routes: {
            VerificationSubmissionPage.routeName: (_) =>
                const VerificationSubmissionPage(roleCode: 'DOCTOR'),
          }),
        ),
      );
      await tester.pumpAndSettle();
      final doctor = find.text('Doctor');
      await tester.ensureVisible(doctor);
      await tester.pumpAndSettle();
      await tester.tap(doctor);
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'doc@example.com');
      await tester.enterText(fields.at(3), 'Str0ngPass9!');
      await tester.enterText(fields.at(4), 'Str0ngPass9!');
      final submit = find.widgetWithText(FilledButton, 'Create Account');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.byType(VerificationSubmissionPage), findsOneWidget);
    });
  });

  group('AuthController AUTH-2 session behaviour', () {
    test('login surfaces doctor verification from the server, never inferred',
        () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/login/');
        return _loginResponse(roles: const ['DOCTOR'], doctorStatus: 'APPROVED');
      });
      final controller = AuthController(
        repository:
            AuthRepository(tokenStore: EphemeralTokenStore(), client: client),
      );
      await controller.login(identifier: 'user@example.com', password: 'x');
      expect(controller.isVerifiedDoctor, isTrue);
      expect(controller.doctorVerificationStatus, 'APPROVED');
      expect(controller.isAuthenticated, isTrue);
    });

    test('restoreSession with a network failure keeps tokens', () async {
      final store = EphemeralTokenStore();
      await store.writeAccess('kept-access');
      final client = MockClient((_) async => throw Exception('offline'));
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await controller.restoreSession();
      expect(controller.status, AuthStatus.unauthenticated);
      expect(controller.isAuthenticated, isFalse);
      expect(await store.readAccess(), 'kept-access');
    });

    test('setLoginPin stores the PIN and remembers the device identity',
        () async {
      final store = EphemeralTokenStore();
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/login/') {
          return _loginResponse(hasLoginPin: false);
        }
        if (request.url.path == '/api/auth/pin/set/') {
          expect(request.headers['Authorization'], 'Bearer access-1');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['pin'], '4821');
          return http.Response('', 204);
        }
        throw Exception('unexpected ${request.url.path}');
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await controller.login(identifier: 'user@example.com', password: 'x');
      expect(controller.hasLoginPin, isFalse);
      await controller.setLoginPin(pin: '4821');
      expect(controller.hasLoginPin, isTrue);
      expect(await store.readRememberedIdentity(), 'user@example.com');
    });

    test('loginWithPin signs in with the remembered identity', () async {
      final store = EphemeralTokenStore();
      await store.writeRememberedIdentity('user@example.com');
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/pin/login/');
        return _loginResponse();
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await controller.restoreSession();
      expect(controller.rememberedIdentity, 'user@example.com');
      await controller.loginWithPin(pin: '4821');
      expect(controller.isAuthenticated, isTrue);
      expect(await store.readAccess(), 'access-1');
    });
  });
}
