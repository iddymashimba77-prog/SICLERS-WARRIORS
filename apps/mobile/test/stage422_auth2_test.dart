import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/auth/data/auth_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/domain/auth_types.dart';
import 'package:sicklers_warriors/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/continue_as_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/doctor_verification_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/email_verification_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/login_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/organization_verification_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/signup_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/widgets/auth_gate.dart';
import 'package:sicklers_warriors/features/auth/presentation/widgets/session_router.dart';
import 'package:sicklers_warriors/features/auth/presentation/widgets/session_scope.dart';
import 'package:sicklers_warriors/features/blood_donation/presentation/pages/donor_shell.dart';
import 'package:sicklers_warriors/features/caregiver/presentation/pages/caregiver_shell.dart';
import 'package:sicklers_warriors/features/doctor/presentation/pages/doctor_shell.dart';
import 'package:sicklers_warriors/features/public/presentation/pages/public_home_page.dart';
import 'package:sicklers_warriors/shared/widgets/main_shell.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Future<void> _phoneViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

MockClient _loginClient(
  List<String> roles, {
  String? doctorStatus,
  Map<String, dynamic>? facility,
}) =>
    MockClient((request) async {
      expect(request.url.path, '/api/auth/login/');
      return _json({
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
          },
        },
      });
    });

Future<AuthController> _login(
  WidgetTester tester,
  MockClient client, {
  Map<String, WidgetBuilder> routes = const {},
}) async {
  final controller = AuthController(
    repository: AuthRepository(tokenStore: EphemeralTokenStore(), client: client),
  );
  await tester.pumpWidget(
    SessionScope(
      controller: controller,
      child: MaterialApp(
        home: LoginPage(controller: controller),
        routes: {
          MainShell.routeName: (_) => const MainShell(),
          DoctorShell.routeName: (_) => const DoctorShell(),
          DonorShell.routeName: (_) => const DonorShell(),
          CaregiverShell.routeName: (_) => const CaregiverShell(),
          DoctorVerificationPage.routeName: (_) =>
              DoctorVerificationPage(controller: controller),
          OrganizationVerificationPage.routeName: (_) =>
              const OrganizationVerificationPage(),
          ContinueAsPage.routeName: (_) => const ContinueAsPage(),
          ...routes,
        },
      ),
    ),
  );
  await tester.enterText(find.byType(TextFormField).at(0), 'user@example.com');
  await tester.enterText(find.byType(TextFormField).at(1), 'Str0ngPass1!');
  await tester.tap(find.widgetWithText(FilledButton, AppStrings.login));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  group('SessionRouter resolves server-asserted verification (AUTH-2)', () {
    test('a verified DOCTOR maps to the clinical dashboard', () {
      final ctx = SessionRouter.resolve(
        roles: ['DOCTOR'],
        doctorVerificationStatus: 'APPROVED',
      );
      expect(ctx?.route, DoctorShell.routeName);
    });

    test('a PENDING/absent DOCTOR never maps to the dashboard', () {
      for (final status in ['PENDING', 'REJECTED', null]) {
        final ctx = SessionRouter.resolve(
          roles: ['DOCTOR'],
          doctorVerificationStatus: status,
        );
        expect(ctx?.route, DoctorVerificationPage.routeName,
            reason: 'status=$status');
      }
    });

    test('HOSPITAL / ORGANIZATION resolve to the organization surface', () {
      for (final role in ['HOSPITAL', 'HEALTHCARE_STAFF', 'ORGANIZATION']) {
        final ctx = SessionRouter.resolve(roles: [role]);
        expect(ctx?.route, OrganizationVerificationPage.routeName,
            reason: role);
      }
    });

    test('PATIENT keeps the five-tab shell default', () {
      final ctx = SessionRouter.resolve(roles: ['PATIENT']);
      expect(ctx?.route, MainShell.routeName);
    });

    test('multi-role sessions never drop a role silently', () {
      final contexts = SessionRouter.contextsFor(
        roles: ['PATIENT', 'BLOOD_DONOR'],
      );
      expect(contexts.length, 2);
      expect(SessionRouter.resolve(roles: ['PATIENT', 'BLOOD_DONOR']), isNull);
    });
  });

  group('AuthController AUTH-2 session behaviour', () {
    test('login surfaces doctor verification from the server, never inferred',
        () async {
      final client = _loginClient(['DOCTOR'], doctorStatus: 'APPROVED');
      final controller = AuthController(
        repository:
            AuthRepository(tokenStore: EphemeralTokenStore(), client: client),
      );
      await controller.login(identifier: 'user@example.com', password: 'x');
      expect(controller.isVerifiedDoctor, isTrue);
      expect(controller.doctorVerificationStatus, 'APPROVED');
      expect(controller.isAuthenticated, isTrue);
    });

    test('restoreSession with a network failure keeps tokens, unmasked',
        () async {
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

    test('restoreSession clears tokens the server rejects (401)', () async {
      final store = EphemeralTokenStore();
      await store.writeAccess('stale');
      final client = MockClient((_) async => _json(
            {'error': {'code': 'TOKEN_EXPIRED', 'message': 'Expired.'}},
            401,
          ));
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await controller.restoreSession();
      expect(controller.status, AuthStatus.unauthenticated);
      expect(await store.readAccess(), isNull);
    });

    test('register (PENDING_VERIFICATION) awaits email verification', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/register/');
        expect(request.method, 'POST');
        return _json({
          'data': {
            'user': {'email': 'new@example.com', 'account_status': 'PENDING_VERIFICATION'},
          },
        }, 201);
      });
      final controller = AuthController(
        repository:
            AuthRepository(tokenStore: EphemeralTokenStore(), client: client),
      );
      await controller.register(
        email: 'new@example.com',
        password: 'Str0ngPass1!',
        roleCode: 'PATIENT',
      );
      expect(controller.lastError, isNull);
      expect(controller.email, 'new@example.com');
      expect(controller.emailVerified, isFalse);
    });

    test('verifyEmail consumes the one-time code on success', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/verify/email/');
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['token'], 'abc-123');
        return http.Response('', 204);
      });
      final controller = AuthController(
        repository:
            AuthRepository(tokenStore: EphemeralTokenStore(), client: client),
      );
      await controller.verifyEmail(token: 'abc-123');
      expect(controller.emailVerified, isTrue);
      expect(controller.lastError, isNull);
    });

    test('verifyEmail propagates a rejected code', () async {
      final client = MockClient((_) async => _json(
            {'error': {'code': 'INVALID_TOKEN', 'message': 'Code expired.'}},
            400,
          ));
      final controller = AuthController(
        repository:
            AuthRepository(tokenStore: EphemeralTokenStore(), client: client),
      );
      await expectLater(
        controller.verifyEmail(token: 'bad'),
        throwsA(isA<AuthException>()),
      );
      expect(controller.emailVerified, isFalse);
      expect(controller.lastError?.message, 'Code expired.');
    });

    test('resendEmailVerification tolerates the uniform 202 reply', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/verify/email/resend/');
        return _json({'data': {'detail': 'ok'}}, 202);
      });
      final controller = AuthController(
        repository:
            AuthRepository(tokenStore: EphemeralTokenStore(), client: client),
      );
      await controller.resendEmailVerification(email: 'new@example.com');
      expect(controller.lastError, isNull);
    });
  });

  group('AUTH-2 flows (widgets)', () {
    testWidgets('AuthGate cold-start with no session lands on Public Home',
        (tester) async {
      final controller = AuthController(
        repository: AuthRepository(tokenStore: EphemeralTokenStore()),
      );
      await controller.restoreSession();
      await tester.pumpWidget(
        SessionScope(
          controller: controller,
          child: MaterialApp(
            initialRoute: AuthGate.routeName,
            routes: {
              AuthGate.routeName: (_) => const AuthGate(),
              PublicHomePage.routeName: (_) => const PublicHomePage(),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PublicHomePage), findsOneWidget);
    });

    testWidgets('multi-role login stops at Continue-as and preserves both roles',
        (tester) async {
      await _phoneViewport(tester);
      final client = _loginClient(['PATIENT', 'BLOOD_DONOR']);
      final controller = await _login(tester, client);
      expect(controller.isAuthenticated, isTrue);
      expect(controller.roles, ['PATIENT', 'BLOOD_DONOR']);
      expect(find.byType(ContinueAsPage), findsOneWidget);
      expect(find.text('Patient'), findsOneWidget);
      expect(find.text('Blood Donor'), findsOneWidget);

      await tester.tap(find.text('Patient'));
      await tester.pumpAndSettle();
      expect(find.byType(MainShell), findsOneWidget);
    });

    testWidgets('a HOSPITAL login lands on the organization surface',
        (tester) async {
      await _phoneViewport(tester);
      final client = _loginClient(
        ['HOSPITAL'],
        facility: {'name': 'Ahero County Hospital', 'is_verified': false},
      );
      final controller = await _login(tester, client);
      expect(controller.facility?['name'], 'Ahero County Hospital');
      expect(find.byType(OrganizationVerificationPage), findsOneWidget);
      expect(find.textContaining('pending'), findsWidgets);
      expect(find.byType(MainShell), findsNothing);
    });

    testWidgets('signup routes into the email-verification flow', (tester) async {
      await _phoneViewport(tester);
      final client = MockClient((request) async {
        switch (request.url.path) {
          case '/api/auth/register/':
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['role_code'], 'PATIENT');
            return _json({
              'data': {
                'user': {
                  'email': 'new@example.com',
                  'account_status': 'PENDING_VERIFICATION',
                },
              },
            }, 201);
          default:
            return _json({'error': {'code': 'NOT_FOUND', 'message': 'Nope'}}, 404);
        }
      });
      final controller = AuthController(
        repository:
            AuthRepository(tokenStore: EphemeralTokenStore(), client: client),
      );
      await tester.pumpWidget(
        SessionScope(
          controller: controller,
          child: MaterialApp(
            home: const SignupPage(),
            routes: {
              EmailVerificationPage.routeName: (_) =>
                  const EmailVerificationPage(email: 'new@example.com'),
              LoginPage.routeName: (_) => const LoginPage(),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'new@example.com');
      await tester.enterText(fields.at(1), 'Warrior');
      await tester.enterText(fields.at(2), 'Star');
      await tester.enterText(fields.at(3), 'Str0ngPass1!');
      await tester.enterText(fields.at(4), 'Str0ngPass1!');
      final create = find.widgetWithText(FilledButton, 'Create Account');
      await tester.ensureVisible(create);
      await tester.pumpAndSettle();
      await tester.tap(create);
      await tester.pumpAndSettle();

      expect(find.byType(EmailVerificationPage), findsOneWidget);
      expect(find.textContaining('new@example.com'), findsOneWidget);
    });

    testWidgets('signup explains roles that are not self-registerable',
        (tester) async {
      await _phoneViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(home: SignupPage()),
      );
      await tester.pumpAndSettle();

      final guidance = find.text('Doctor, hospital or organization?');
      await tester.ensureVisible(guidance);
      await tester.pumpAndSettle();
      await tester.tap(guidance);
      await tester.pumpAndSettle();
      expect(find.text('Professional or organization sign-up'), findsOneWidget);
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('Hospital / Clinic'), findsOneWidget);
    });

    testWidgets('email verification accepts the code and lands on login',
        (tester) async {
      await _phoneViewport(tester);
      final client = MockClient((request) async {
        switch (request.url.path) {
          case '/api/auth/verify/email/':
            expect(request.method, 'POST');
            return http.Response('', 204);
          case '/api/auth/verify/email/resend/':
            return _json({'data': {'detail': 'sent'}}, 202);
          default:
            return _json({'error': {'code': 'NOT_FOUND', 'message': 'Nope'}}, 404);
        }
      });
      final controller = AuthController(
        repository:
            AuthRepository(tokenStore: EphemeralTokenStore(), client: client),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EmailVerificationPage(
            email: 'new@example.com',
            controller: controller,
          ),
          routes: {LoginPage.routeName: (_) => const LoginPage()},
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'verify-1');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify Email'));
      await tester.pumpAndSettle();

      expect(controller.emailVerified, isTrue);
      expect(find.text('Email verified'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Go to Login'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('invalid verification code surfaces the error inline',
        (tester) async {
      await _phoneViewport(tester);
      final client = MockClient((_) async => _json(
            {'error': {'code': 'INVALID_TOKEN', 'message': 'That code has expired.'}},
            400,
          ));
      final controller = AuthController(
        repository:
            AuthRepository(tokenStore: EphemeralTokenStore(), client: client),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EmailVerificationPage(
            email: 'new@example.com',
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify Email'));
      await tester.pumpAndSettle();

      expect(controller.emailVerified, isFalse);
      expect(find.text('That code has expired.'), findsOneWidget);
    });
  });
}