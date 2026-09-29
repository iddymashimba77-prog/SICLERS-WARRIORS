import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/health/presentation/pages/health_dashboard_page.dart';
import 'package:sicklers_warriors/features/medication/data/medication_repository.dart';
import 'package:sicklers_warriors/features/medication/presentation/pages/medication_page.dart';

Map<String, dynamic> _medicationsPayload() => {
      'data': {
        'results': [
          {
            'uid': 'med-1',
            'name': 'Hydroxyurea',
            'generic_name': 'Hydroxycarbamide',
            'strength': '500 mg',
            'dosage': '1 tablet',
            'route': 'ORAL',
            'frequency': 'daily',
            'is_active': true,
            'schedules': [
              {
                'uid': 'sched-1',
                'time_of_day': '08:00:00',
                'days_of_week': const ['MON', 'WED'],
                'notes': '',
              },
            ],
          },
        ],
      },
      'meta': {'count': 1},
    };

Map<String, dynamic> _statsPayload() => {
      'data': {
        'window_days': 30,
        'overall': {
          'expected': 4,
          'taken': 3,
          'missed': 1,
          'skipped': 0,
          'snoozed': 0,
          'non_adherent': 1,
          'adherence_pct': 75.0,
        },
        'per_medication': [],
      }
    };

MockClient _happyClient() {
  return MockClient((request) async {
    if (request.url.path.endsWith('/medications/stats/')) {
      return http.Response(jsonEncode(_statsPayload()), 200,
          headers: {'content-type': 'application/json'});
    }
    if (request.url.path.endsWith('/medications/')) {
      return http.Response(jsonEncode(_medicationsPayload()), 200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response('not found', 404);
  });
}

void main() {
  testWidgets('MedicationPage guards when signed out', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MedicationPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.notSignedIn), findsOneWidget);
  });

  testWidgets('HealthDashboardPage guards when signed out', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HealthDashboardPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.notSignedIn), findsOneWidget);
  });

  testWidgets('MedicationHomeView loads and lists medications', (tester) async {
    final store = EphemeralTokenStore();
    final repo = MedicationRepository(
      tokenStore: store,
      client: _happyClient(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MedicationHomeView(
          accessToken: 'test-access',
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hydroxyurea 500 mg'), findsOneWidget);
  });
}