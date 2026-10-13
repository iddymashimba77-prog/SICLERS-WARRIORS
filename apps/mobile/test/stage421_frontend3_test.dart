import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/admin/presentation/pages/admin_panel_page.dart';
import 'package:sicklers_warriors/features/auth/data/auth_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/change_password_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/login_page.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/doctor_verification_page.dart';
import 'package:sicklers_warriors/features/blood_donation/presentation/pages/donor_shell.dart';
import 'package:sicklers_warriors/features/caregiver/presentation/pages/caregiver_shell.dart';
import 'package:sicklers_warriors/features/clinic/presentation/pages/clinic_page.dart';
import 'package:sicklers_warriors/features/doctor/presentation/pages/doctor_shell.dart';
import 'package:sicklers_warriors/features/doctor_network/presentation/pages/doctor_network_page.dart';
import 'package:sicklers_warriors/features/health/data/health_repository.dart';
import 'package:sicklers_warriors/features/health/presentation/pages/health_dashboard_page.dart';
import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/features/medical/presentation/pages/medical_records_page.dart';
import 'package:sicklers_warriors/shared/widgets/main_shell.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Future<void> _tallViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

MockClient _loginClient(List<String> roles) => MockClient((request) async {
      expect(request.url.path, '/api/auth/login/');
      expect(request.method, 'POST');
      return _json({
        'data': {
          'access': 'access-1',
          'refresh': 'refresh-1',
          'user': {
            'email': 'user@example.com',
            'account_status': 'ACTIVE',
            'has_login_pin': true,
            'role_codes': roles,
            // AUTH-2: clinical access requires server-asserted APPROVED.
            'doctor_verification_status':
                roles.contains('DOCTOR') ? 'APPROVED' : null,
          },
        },
      });
    });

/// Stub so the routing group does not depend on the emergency module.
class _EmergencyRoute extends StatelessWidget {
  const _EmergencyRoute();

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

/// Logs in as [roles] and settles on the post-login shell.
Future<void> _login(WidgetTester tester, List<String> roles) async {
  await _tallViewport(tester);
  final controller = AuthController(
    repository:
        AuthRepository(tokenStore: EphemeralTokenStore(), client: _loginClient(roles)),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: LoginPage(controller: controller),
      routes: {
        MainShell.routeName: (_) => const MainShell(),
        DoctorShell.routeName: (_) => const DoctorShell(),
        DonorShell.routeName: (_) => const DonorShell(),
        CaregiverShell.routeName: (_) => const CaregiverShell(),
        AdminPanelPage.routeName: (_) => const AdminPanelPage(),
        DoctorVerificationPage.routeName: (_) => const DoctorVerificationPage(),
        '/emergency': (_) => const _EmergencyRoute(),
      },
    ),
  );
  await tester.enterText(find.byType(TextFormField).at(0), 'user@example.com');
  await tester.enterText(find.byType(TextFormField).at(1), 'Str0ngPass1!');
  await tester.tap(find.widgetWithText(FilledButton, AppStrings.login));
  await tester.pumpAndSettle();
}

/// Authenticated controller backed by [client] (mirrors FRONTEND-2 tests).
Future<AuthController> _authenticated(MockClient client) async {
  final store = EphemeralTokenStore();
  await store.writeAccess('access-1');
  await store.writeRefresh('refresh-1');
  final controller = AuthController(
    repository: AuthRepository(tokenStore: store, client: client),
  );
  await controller.restoreSession();
  return controller;
}

Map<String, dynamic> _emptyDashboard() => {
      'generated_at': '2026-09-26T10:00:00Z',
      'medications': const {
        'active_count': 0,
        'doses_today': {},
        'list': <Object>[],
      },
      'adherence_last_7_days': const {},
      'recent_symptoms': const [],
      'recent_timeline': const [],
    };

void main() {
  group('Role-based post-login routing (FRONTEND-3)', () {
    testWidgets('PATIENT still lands on the five-tab patient shell',
        (tester) async {
      await _login(tester, ['PATIENT']);
      expect(find.byType(MainShell), findsOneWidget);
    });
    testWidgets('DOCTOR lands on the doctor shell (no patient shell)',
        (tester) async {
      await _login(tester, ['DOCTOR']);
      expect(find.byType(DoctorShell), findsOneWidget);
      expect(find.byType(MainShell), findsNothing);
    });
    testWidgets(
        'an unverified DOCTOR lands on the verification screen, never a clinical dashboard '
        '(AUTH-2 account type is not verification)', (tester) async {
      await _tallViewport(tester);
      final controller = AuthController(
        repository: AuthRepository(
          tokenStore: EphemeralTokenStore(),
          client: MockClient((request) async {
            expect(request.url.path, '/api/auth/login/');
            return _json({
              'data': {
                'access': 'access-1',
                'refresh': 'refresh-1',
                'user': {
                  'email': 'doctor@example.com',
                  'account_status': 'ACTIVE',
                  'has_login_pin': true,
                  'role_codes': ['DOCTOR'],
                  'doctor_verification_status': 'PENDING',
                },
              },
            });
          }),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(controller: controller),
          routes: {
            DoctorVerificationPage.routeName: (_) =>
                DoctorVerificationPage(controller: controller),
          },
        ),
      );
      await tester.enterText(
          find.byType(TextFormField).at(0), 'doctor@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'Str0ngPass1!');
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.login));
      await tester.pumpAndSettle();

      expect(find.byType(DoctorVerificationPage), findsOneWidget);
      expect(find.byType(DoctorShell), findsNothing);
      expect(find.text('Verification pending'), findsOneWidget);
    });
    testWidgets('BLOOD_DONOR lands on the donor shell', (tester) async {
      await _login(tester, ['BLOOD_DONOR']);
      expect(find.byType(DonorShell), findsOneWidget);
    });
    testWidgets('CAREGIVER lands on the caregiver shell', (tester) async {
      await _login(tester, ['CAREGIVER']);
      expect(find.byType(CaregiverShell), findsOneWidget);
    });
    testWidgets('ADMIN lands on the admin panel', (tester) async {
      await _login(tester, ['ADMIN']);
      expect(find.byType(AdminPanelPage), findsOneWidget);
    });
  });

  group('Change password (FRONTEND-3)', () {
    testWidgets('success revokes every session and signs the user back out',
        (tester) async {
      await _tallViewport(tester);
      final store = EphemeralTokenStore();
      final client = MockClient((request) async {
        switch (request.url.path) {
          case '/api/auth/password/change/':
            expect(request.method, 'POST');
            return _json({'data': {'detail': 'Password changed.'}});
          case '/api/auth/logout/':
            return _json({'data': {}});
          default:
            return _json({'error': {'code': 'NOT_FOUND', 'message': 'Missing.'}}, 404);
        }
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await store.writeAccess('access-1');
      await store.writeRefresh('refresh-1');

      await tester.pumpWidget(
        MaterialApp(
          home: ChangePasswordPage(
            accessToken: 'access-1',
            controller: controller,
            repository: AuthRepository(tokenStore: store, client: client),
          ),
          routes: {LoginPage.routeName: (_) => const LoginPage()},
        ),
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'OldPass1!');
      await tester.enterText(fields.at(1), 'Str0ngPass1!');
      await tester.enterText(fields.at(2), 'Str0ngPass1!');
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.updatePassword));
      await tester.pumpAndSettle();

      // Backend revokes all sessions → local session ends and re-login is forced.
      expect(controller.isAuthenticated, isFalse);
      expect(await store.readAccess(), isNull);
      expect(find.text(AppStrings.passwordChanged), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, AppStrings.close));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('a backend rejection keeps the form and shows the error',
        (tester) async {
      await _tallViewport(tester);
      final store = EphemeralTokenStore();
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/password/change/') {
          return _json({
            'error': {
              'code': 'CURRENT_PASSWORD_INCORRECT',
              'message': 'Current password is incorrect.',
            },
          }, 400);
        }
        return _json({'error': {'code': 'NOT_FOUND', 'message': 'Missing.'}}, 404);
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangePasswordPage(
            accessToken: 'access-1',
            controller: controller,
            repository: AuthRepository(tokenStore: store, client: client),
          ),
        ),
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'WrongPass!');
      await tester.enterText(fields.at(1), 'Str0ngPass1!');
      await tester.enterText(fields.at(2), 'Str0ngPass1!');
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.updatePassword));
      await tester.pumpAndSettle();

      expect(find.byType(ChangePasswordPage), findsOneWidget);
      expect(find.text('Current password is incorrect.'), findsOneWidget);
    });

    testWidgets('client-side validation blocks mismatched confirmation before the network',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangePasswordPage(
            accessToken: 'access-1',
            repository: AuthRepository(tokenStore: EphemeralTokenStore()),
          ),
        ),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'OldPass1!');
      await tester.enterText(fields.at(1), 'Str0ngPass1!');
      await tester.enterText(fields.at(2), 'OtherPass1!');
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.updatePassword));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.passwordsDoNotMatch), findsOneWidget);
    });
  });

  group('Honest empty states where no backend service exists (FRONTEND-3)', () {
    testWidgets('Health Records never fabricates records when signed out',
        (tester) async {
      // The chart API is live now, but with no session the page must still show
      // an honest state rather than inventing rows (see medrec_records_test.dart
      // for the signed-in surface).
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: materialLocalizationsDelegates(
            LocaleController(AppPreferences.memory()),
          ),
          supportedLocales: AppLocalizationsDelegate.supportedLocales,
          home: const MedicalRecordsPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No records are shared with you yet.'),
        findsOneWidget,
      );
    });

    testWidgets('Doctor Network never lists unverified doctors',
        (tester) async {
      // The registry is live now; signed out there is nothing to browse and
      // nothing is invented (see doctor_directory_test.dart for the list).
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: materialLocalizationsDelegates(
            LocaleController(AppPreferences.memory()),
          ),
          supportedLocales: AppLocalizationsDelegate.supportedLocales,
          home: const DoctorNetworkPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Sign in to browse verified professionals.'),
        findsOneWidget,
      );
    });

    testWidgets('Clinic shows no fabricated appointments when signed out',
        (tester) async {
      // The appointment API is live now; signed out, the calendar must still
      // show an honest state rather than inventing a booking
      // (see clinic_appointments_test.dart for the signed-in surface).
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: materialLocalizationsDelegates(
            LocaleController(AppPreferences.memory()),
          ),
          supportedLocales: AppLocalizationsDelegate.supportedLocales,
          home: const ClinicPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('You have no appointments booked yet.'),
        findsOneWidget,
      );
    });
  });

  group('Tiba landing quick actions (FRONTEND-3)', () {
    testWidgets('quick actions + honest sections render from a real empty dashboard',
        (tester) async {
      await _tallViewport(tester);
      final client = MockClient((request) async {
        switch (request.url.path) {
          case '/api/auth/token/refresh/':
            return _json({'data': {'access': 'access-2', 'refresh': 'refresh-2'}});
          case '/api/auth/me/':
            return _json({
              'data': {
                'email': 'warrior@example.com',
                'account_status': 'ACTIVE',
                'role_codes': ['PATIENT'],
              },
            });
          case '/api/patients/me/dashboard/':
            return _json({'data': _emptyDashboard()});
          default:
            return _json({'error': {'code': 'NOT_FOUND', 'message': 'Missing.'}}, 404);
        }
      });
      final auth = await _authenticated(client);
      await tester.pumpWidget(
        MaterialApp(
          // The real app always registers these; without them a page renders
          // through the Swahili fallback instance.
          localizationsDelegates: materialLocalizationsDelegates(
            LocaleController(AppPreferences.memory()),
          ),
          supportedLocales: AppLocalizationsDelegate.supportedLocales,
          home: HealthDashboardPage(
            authController: auth,
            healthRepository:
                HealthRepository(tokenStore: EphemeralTokenStore(), client: client),
          ),
          routes: {
            MedicalRecordsPage.routeName: (_) => const MedicalRecordsPage(),
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.tibaSubtitle), findsOneWidget);
      expect(find.text(AppStrings.manageMedications), findsOneWidget);
      expect(find.text(AppStrings.logSymptomShort), findsOneWidget);
      expect(find.text(AppStrings.viewTimelineShort), findsOneWidget);
      expect(find.text(AppStrings.healthRecords), findsOneWidget);
      // Honest records + care-plan sections (no fabricated data).
      expect(find.text(AppStrings.noHealthRecords), findsOneWidget);
      expect(find.text(AppStrings.carePlanUnavailable), findsOneWidget);

      // Records quick action opens the honest records surface.
      await tester.tap(find.text(AppStrings.healthRecords));
      await tester.pumpAndSettle();
      expect(find.byType(MedicalRecordsPage), findsOneWidget);
      // Signed out (the fallback session has no token), so the chart shows the
      // honest empty state instead of contacting the API.
      expect(
        find.textContaining('No records are shared with you yet.'),
        findsOneWidget,
      );
    });
  });
}