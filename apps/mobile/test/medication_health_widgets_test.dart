import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/health/presentation/pages/health_dashboard_page.dart';
import 'package:sicklers_warriors/features/medication/data/medication_repository.dart';
import 'package:sicklers_warriors/features/medication/presentation/pages/medication_detail_page.dart';
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
            'instructions': 'Take with food. Avoid alcohol.',
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
    if (request.url.path.contains('/schedule') ||
        request.url.path.endsWith('/events/')) {
      return http.Response(
        jsonEncode({
          'data': {'results': const <dynamic>[]},
          'meta': {'count': 0},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
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

/// Instructions must survive the round trip (`FR-MED-007`): the DTO reads the
/// server field, the form writes it back, and the detail screen shows it.
void main() {
  testWidgets('the detail screen shows the prescriber instructions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: materialLocalizationsDelegates(
          LocaleController(AppPreferences.memory()),
        ),
        supportedLocales: AppLocalizationsDelegate.supportedLocales,
        home: MedicationDetailPage(
          accessToken: 'test-access',
          repository: MedicationRepository(
            tokenStore: EphemeralTokenStore(),
            client: _happyClient(),
          ),
          medication: Medication.fromJson(
            _medicationsPayload()['data']['results'][0],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Instructions'), findsOneWidget);
    expect(find.text('Take with food. Avoid alcohol.'), findsOneWidget);
  });

  testWidgets('no instructions means no empty card', (tester) async {
    final row = Map<String, dynamic>.from(_medicationsPayload()['data']['results'][0])
      ..remove('instructions');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: materialLocalizationsDelegates(
          LocaleController(AppPreferences.memory()),
        ),
        supportedLocales: AppLocalizationsDelegate.supportedLocales,
        home: MedicationDetailPage(
          accessToken: 'test-access',
          repository: MedicationRepository(
            tokenStore: EphemeralTokenStore(),
            client: _happyClient(),
          ),
          medication: Medication.fromJson(row),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Instructions'), findsNothing);
  });

  test('instructions travel with the medication', () {
    final med = Medication.fromJson(_medicationsPayload()['data']['results'][0]);
    expect(med.instructions, 'Take with food. Avoid alcohol.');
    expect(med.toJson()['instructions'], 'Take with food. Avoid alcohol.');
  });

  test('a medication without instructions reads as blank, not null', () {
    final row = Map<String, dynamic>.from(_medicationsPayload()['data']['results'][0])
      ..remove('instructions');
    final med = Medication.fromJson(row);
    expect(med.instructions, isEmpty);
    expect(med.toJson()['instructions'], '');
  });

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