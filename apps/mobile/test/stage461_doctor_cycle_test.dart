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
import 'package:sicklers_warriors/features/auth/presentation/widgets/session_router.dart';
import 'package:sicklers_warriors/features/doctor/presentation/pages/doctor_medications_page.dart';
import 'package:sicklers_warriors/features/health/data/health_repository.dart';
import 'package:sicklers_warriors/features/medication/data/medication_repository.dart';
import 'package:sicklers_warriors/features/medication/presentation/pages/medication_page.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _medicationRow() => {
  'uid': 'med-1',
  'name': 'Hydroxyurea',
  'generic_name': 'Hydroxycarbamide',
  'strength': '500 mg',
  'dosage': '1 tablet',
  'route': 'ORAL',
  'frequency': 'daily',
  'instructions': 'Take with food.',
  'is_active': true,
  'schedules': <dynamic>[],
};

List<Map<String, dynamic>> _directory() => [
  {'uid': 'pat-1', 'email': 'asha@example.com', 'full_name': 'Asha Juma'},
];

/// Verified-prescriber flow (Stage 4.6): directory → one patient's
/// medications → one patient's symptom log. Mirrors the backend contract the
/// doctor cycle added (`/api/patients/directory/`, `?patient=<uid>` filters).
MockClient _doctorClient() {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/patients/directory/')) {
      return _json(_directory());
    }
    if (path.endsWith('/medications/')) {
      return _json({
        'data': {
          'results': [_medicationRow()],
        },
        'meta': {'count': 1},
      });
    }
    if (path.endsWith('/symptoms/')) {
      return _json({
        'data': {
          'results': [
            {
              'uid': 'sym-1',
              'symptom_type_code': 'chest_pain',
              'symptom_type_name': 'Chest pain',
              'pain_level': 7,
              'triggers': const <String>['cold'],
              'duration_minutes': 45,
              'notes': '',
              'recorded_at': '2026-10-08T09:30:00Z',
            },
          ],
        },
        'meta': {'count': 1},
      });
    }
    return http.Response('not found', 404);
  });
}

void main() {
  group('Patient view-only medications (Stage 4.6)', () {
    testWidgets('list renders without any add affordance', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MedicationHomeView(
            accessToken: 'test-access',
            repository: MedicationRepository(
              tokenStore: EphemeralTokenStore(),
              client: MockClient(
                (request) async => _json({
                  'data': {
                    'results': [_medicationRow()],
                  },
                  'meta': {'count': 1},
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hydroxyurea 500 mg'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text(AppStrings.addMedication), findsNothing);
    });

    testWidgets('empty list shows the neutral message, still no add button', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MedicationHomeView(
            accessToken: 'test-access',
            repository: MedicationRepository(
              tokenStore: EphemeralTokenStore(),
              client: MockClient(
                (request) async => _json({
                  'data': {'results': const <dynamic>[]},
                  'meta': {'count': 0},
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.noMedications), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text(AppStrings.addMedication), findsNothing);
    });
  });

  group('Doctor medications + symptoms (Stage 4.6)', () {
    testWidgets('directory, medications and symptom log load for a patient', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: materialLocalizationsDelegates(
            LocaleController(AppPreferences.memory()),
          ),
          supportedLocales: AppLocalizationsDelegate.supportedLocales,
          home: Scaffold(
            body: DoctorMedicationsView(
              accessToken: 'test-access',
              repository: MedicationRepository(
                tokenStore: EphemeralTokenStore(),
                client: _doctorClient(),
              ),
              healthRepository: HealthRepository(
                tokenStore: EphemeralTokenStore(),
                client: _doctorClient(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Asha Juma'), findsWidgets);
      expect(find.text('Hydroxyurea 500 mg'), findsOneWidget);
      expect(find.text(AppStrings.addMedication), findsOneWidget);
      expect(find.text('Chest pain'), findsOneWidget);
      expect(find.textContaining('7'), findsWidgets);
    });
  });

  group('Unknown administrative roles (REQ-4)', () {
    test('an unrecognized role resolves to the role workspace', () {
      final ctx = SessionRouter.resolve(roles: ['COUNSELLOR']);
      expect(ctx?.route, '/role-workspace');
      expect(ctx?.id, 'workspace');
    });

    test('a known role next to an unknown one never drops the workspace', () {
      final contexts = SessionRouter.contextsFor(
        roles: ['PATIENT', 'COUNSELLOR'],
      );
      expect(contexts.any((c) => c.id == 'workspace'), isTrue);
      expect(contexts.any((c) => c.id == 'patient'), isTrue);
      expect(SessionRouter.resolve(roles: ['PATIENT', 'COUNSELLOR']), isNull);
    });

    test('known roles are unaffected', () {
      final ctx = SessionRouter.resolve(roles: ['HOSPITAL']);
      expect(ctx?.route, '/org-status');
    });
  });
}
