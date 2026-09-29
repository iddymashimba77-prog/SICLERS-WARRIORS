import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/auth/data/auth_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sicklers_warriors/features/home/data/home_dashboard_loader.dart';
import 'package:sicklers_warriors/features/home/presentation/pages/home_page.dart';
import 'package:sicklers_warriors/shared/widgets/app_emergency.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Future<void> _tallViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Map<String, dynamic> _dashboard({
  bool hasData = true,
}) {
  if (!hasData) {
    return {
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
  }
  return {
    'generated_at': '2026-09-26T10:00:00Z',
    'medications': {
      'active_count': 1,
      'doses_today': {'expected': 3, 'taken': 1, 'pending': 2},
      'list': [
        {
          'uid': 'm1',
          'name': 'Hydroxyurea',
          'strength': '500 mg',
          'is_active': true,
          'doses_today': {'expected': 3, 'pending': 2},
        },
      ],
    },
    'adherence_last_7_days': {
      'expected': 21,
      'taken': 19,
      'missed': 2,
      'skipped': 0,
      'snoozed': 0,
      'non_adherent': 2,
      'adherence_pct': 90.48,
    },
    'recent_symptoms': [
      {
        'uid': 's1',
        'symptom_type_code': 'PAIN',
        'symptom_type_name': 'Painful crisis',
        'pain_level': 7,
        'triggers': <String>[],
        'duration_minutes': 45,
        'notes': '',
        'recorded_at': '2026-09-26T08:00:00Z',
      },
    ],
    'recent_timeline': [
      {
        'event_type': 'SYMPTOM',
        'occurred_at': '2026-09-26T08:00:00Z',
        'summary': 'Recorded a symptom',
        'payload': <String, dynamic>{},
      },
    ],
  };
}

MockClient _client({
  bool hasData = true,
  bool offline = false,
  bool activeEmergency = false,
  bool openBloodRequest = false,
}) {
  return MockClient((request) async {
    if (offline &&
        request.url.path != '/api/auth/me/' &&
        request.url.path != '/api/education/content/') {
      throw http.ClientException('Offline', request.url);
    }
    switch (request.url.path) {
      case '/api/patients/me/dashboard/':
        return _json({'data': _dashboard(hasData: hasData)});
      case '/api/auth/me/':
        return _json({
          'data': {
            'email': 'warrior@example.com',
            'first_name': 'Amina',
            'last_name': 'Mwaka',
            'account_status': 'ACTIVE',
            'role_codes': ['PATIENT'],
          },
        });
      case '/api/notifications/unread-count/':
        return _json({'data': {'unread': 3}});
      case '/api/education/content/':
        return _json({
          'data': {
            'results': [
              {
                'id': 1,
                'uid': 'edu-1',
                'author': {'uid': 'a1', 'display_name': 'Dr. Chen'},
                'title': 'Managing daily fatigue',
                'body': 'Rest and hydration help.',
                'category': {
                  'id': 1,
                  'code': 'DAILY_LIVING',
                  'name': 'Daily living',
                },
                'status': 'PUBLISHED',
                'published_at': '2026-09-01T00:00:00Z',
              },
            ],
          },
        });
      case '/api/emergency/requests/':
        return _json({
          'data': {
            'results': activeEmergency
                ? [
                    {
                      'uid': 'e1',
                      'severity': 'CRITICAL',
                      'type': 'PAIN_CRISIS',
                      'description': '',
                      'status': 'ACTIVE',
                      'rate_limit_ok': true,
                      'phone_verified': true,
                    },
                  ]
                : <Object>[],
          },
        });
      case '/api/blood/requests/':
        return _json({
          'data': {
            'results': openBloodRequest
                ? [
                    {
                      'uid': 'b1',
                      'blood_group_needed': 'O-',
                      'units': 2,
                      'urgency': 'URGENT',
                      'status': 'ACTIVE',
                      'reason': '',
                      'facility': null,
                    },
                  ]
                : <Object>[],
          },
        });
      default:
        return _json({'data': <String, dynamic>{}});
    }
  });
}

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

void main() {
  group('Home dashboard (FRONTEND-2)', () {
    testWidgets('personalised header uses the real identity from /auth/me',
        (tester) async {
      await _tallViewport(tester);
      final client = _client();
      final auth = await _authenticated(client);
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            controller: auth,
            loader: HomeDashboardLoader(client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Habari, Amina Mwaka'), findsOneWidget);
      expect(find.text(AppStrings.dailyCheckin), findsOneWidget);
      // Unread badge from the real notifications count.
      expect(find.text('3'), findsWidgets);
      // Snapshot uses real dashboard numbers (doses taken/expected).
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('Painful crisis'), findsOneWidget);
      expect(find.text(AppStrings.youAreOffline), findsNothing);
    });

    testWidgets('empty states are honest — no fabricated health data',
        (tester) async {
      await _tallViewport(tester);
      final client = _client(hasData: false);
      final auth = await _authenticated(client);
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            controller: auth,
            loader: HomeDashboardLoader(client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.noMedications), findsOneWidget);
      expect(find.text(AppStrings.noAppointments), findsOneWidget);
      expect(find.text(AppStrings.noActiveAlerts), findsOneWidget);
      expect(find.text(AppStrings.noRecentActivity), findsOneWidget);
    });

    testWidgets('a real active emergency surfaces the red EmergencyCard',
        (tester) async {
      await _tallViewport(tester);
      final client = _client(activeEmergency: true);
      final auth = await _authenticated(client);
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            controller: auth,
            loader: HomeDashboardLoader(client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmergencyCard), findsOneWidget);
      expect(find.text(AppStrings.activeEmergencyTitle), findsOneWidget);
    });

    testWidgets('an open blood request shows the amber alert (not red)',
        (tester) async {
      await _tallViewport(tester);
      final client = _client(openBloodRequest: true);
      final auth = await _authenticated(client);
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            controller: auth,
            loader: HomeDashboardLoader(client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmergencyCard), findsNothing);
      expect(find.text(AppStrings.openBloodRequestTitle), findsOneWidget);
    });

    testWidgets('offline failures show an honest offline state instead of data',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = _client(offline: true);
      final auth = await _authenticated(client);
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            controller: auth,
            loader: HomeDashboardLoader(client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.youAreOffline), findsOneWidget);
      // No fabricated health figures.
      expect(find.text('Painful crisis'), findsNothing);
    });

    testWidgets('a signed-out Home renders the signed-out message', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      expect(find.text(AppStrings.notSignedIn), findsOneWidget);
    });
  });
}