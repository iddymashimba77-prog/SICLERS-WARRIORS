import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/auth/data/auth_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sicklers_warriors/features/auth/presentation/pages/login_page.dart';
import 'package:sicklers_warriors/features/donations/presentation/pages/changia_hub_page.dart';
import 'package:sicklers_warriors/features/doctor/presentation/pages/doctor_hub_page.dart';
import 'package:sicklers_warriors/features/emergency/presentation/pages/emergency_page.dart';
import 'package:sicklers_warriors/features/health/presentation/pages/health_dashboard_page.dart';
import 'package:sicklers_warriors/features/profile/presentation/pages/profile_page.dart';
import 'package:sicklers_warriors/shared/widgets/main_shell.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// Phone viewport (390 x 844 logical px) so the shell uses the bottom nav.
Future<void> _phoneViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: const MainShell(),
      routes: {
        EmergencyPage.routeName: (_) => const EmergencyPage(),
      },
    ),
  );
  await tester.pump();
}

void main() {
  group('MainShell adaptive navigation (FRONTEND-1)', () {
    testWidgets('phone shows the five Swahili destinations + global SOS action',
        (tester) async {
      await _phoneViewport(tester);
      await _pumpShell(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      Finder inNav(String label) => find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          );
      expect(inNav(AppStrings.navHome), findsOneWidget);
      expect(inNav(AppStrings.navDoctor), findsOneWidget);
      expect(inNav(AppStrings.navTreatment), findsOneWidget);
      expect(inNav(AppStrings.navDonate), findsOneWidget);
      expect(inNav(AppStrings.navProfile), findsOneWidget);

      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);
      expect(tester.widget<FloatingActionButton>(fab).tooltip, AppStrings.sos);
    });

    testWidgets('desktop uses a navigation rail with extended labels',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpShell(tester);

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      for (final label in [
        AppStrings.navHome,
        AppStrings.navDoctor,
        AppStrings.navTreatment,
        AppStrings.navDonate,
        AppStrings.navProfile,
      ]) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('tabs switch the body surface', (tester) async {
      await _phoneViewport(tester);
      await _pumpShell(tester);

      await tester.tap(find.text(AppStrings.navDoctor));
      await tester.pump();
      expect(find.byType(DoctorHubPage, skipOffstage: false), findsOneWidget);

      await tester.tap(find.text(AppStrings.navTreatment));
      await tester.pump();
      expect(
          find.byType(HealthDashboardPage, skipOffstage: false), findsOneWidget);

      await tester.tap(find.text(AppStrings.navDonate));
      await tester.pump();
      expect(
          find.byType(ChangiaHubPage, skipOffstage: false), findsOneWidget);

      await tester.tap(find.text(AppStrings.navProfile));
      await tester.pump();
      expect(find.byType(ProfilePage, skipOffstage: false), findsOneWidget);
    });

    testWidgets('SOS action navigates to the emergency surface',
        (tester) async {
      await _phoneViewport(tester);
      await _pumpShell(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(EmergencyPage), findsOneWidget);
      // Signed out: the emergency surface guards behind auth.
      expect(find.text(AppStrings.notSignedIn), findsOneWidget);
    });
  });

  group('Login → shell routing (Stage 4.19)', () {
    MockClient loginClient() => MockClient((request) async {
          expect(request.url.path, '/api/auth/login/');
          expect(request.method, 'POST');
          return _json({
            'data': {
              'access': 'access-1',
              'refresh': 'refresh-1',
              'user': {
                'email': 'warrior@example.com',
                'account_status': 'ACTIVE',
                'role_codes': ['PATIENT'],
              },
            },
          });
        });

    testWidgets('a successful login replaces the login page with the shell',
        (tester) async {
      await _phoneViewport(tester);
      final store = EphemeralTokenStore();
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: loginClient()),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(controller: controller),
          routes: {
            MainShell.routeName: (_) => const MainShell(),
            EmergencyPage.routeName: (_) => const EmergencyPage(),
          },
        ),
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'warrior@example.com');
      await tester.enterText(fields.at(1), 'Str0ngPass1!');
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.login));
      await tester.pumpAndSettle();

      expect(controller.isAuthenticated, isTrue);
      expect(controller.roles, ['PATIENT']);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(MainShell), findsOneWidget);
      expect(await store.readAccess(), 'access-1');
      expect(await store.readRefresh(), 'refresh-1');
    });

    testWidgets('a rejected login stays on the login page with an error',
        (tester) async {
      await _phoneViewport(tester);
      final client = MockClient((request) async {
        return _json({'error': {'code': 'INVALID_CREDENTIALS',
            'message': 'Invalid credentials.'}}, 401);
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: EphemeralTokenStore(), client: client),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(controller: controller),
          routes: {MainShell.routeName: (_) => const MainShell()},
        ),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'warrior@example.com');
      await tester.enterText(fields.at(1), 'WrongPass1!');
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.login));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      expect(controller.lastError?.message, 'Invalid credentials.');
      expect(find.text('Invalid credentials.'), findsOneWidget);
    });
  });
}