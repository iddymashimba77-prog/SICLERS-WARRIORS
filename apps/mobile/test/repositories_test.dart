import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/features/health/data/health_repository.dart';
import 'package:sicklers_warriors/features/medication/data/medication_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/domain/auth_types.dart';

const _token = 'test-access';

Map<String, dynamic> _envelope(String path) {
  if (path == 'medications/list.json') {
    return {
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
              {'uid': 'sched-1', 'time_of_day': '08:00:00', 'days_of_week': ['MON'], 'notes': ''},
            ],
          },
        ],
      },
      'meta': {'count': 1},
    };
  }
  if (path == 'log-dose.json') {
    return {
      'data': {
        'id': 12,
        'schedule_uid': 'sched-1',
        'status': 'TAKEN',
        'taken_at': '2026-09-16T08:05:00Z',
        'note': '',
        'created_at': '2026-09-16T08:05:00Z',
      }
    };
  }
  if (path == 'dashboard.json') {
    return {
      'data': {
        'generated_at': '2026-09-16T09:00:00Z',
        'medications': {
          'active_count': 1,
          'doses_today': {'expected': 2, 'taken': 1, 'pending': 1},
          'list': [
            {
              'uid': 'med-1',
              'name': 'Hydroxyurea',
              'strength': '500 mg',
              'is_active': true,
              'doses_today': {'expected': 2, 'pending': 1},
            },
          ],
        },
        'adherence_last_7_days': {
          'expected': 14,
          'taken': 12,
          'missed': 1,
          'skipped': 1,
          'snoozed': 0,
          'non_adherent': 2,
          'adherence_pct': 85.7,
        },
        'recent_symptoms': [
          {
            'uid': 'sym-1',
            'symptom_type_code': 'PAIN',
            'symptom_type_name': 'Pain',
            'pain_level': 8,
            'triggers': ['Cold'],
            'duration_minutes': 45,
            'notes': '',
            'recorded_at': '2026-09-16T07:30:00Z',
          },
        ],
        'recent_timeline': [
          {
            'event_type': 'DOSE_LOGGED',
            'occurred_at': '2026-09-16T08:05:00Z',
            'summary': 'Dose logged for Hydroxyurea',
            'payload': {'status': 'TAKEN'},
          },
        ],
      }
    };
  }
  return {'data': {}};
}

void main() {
  final store = EphemeralTokenStore();

  test('listMedications unwraps envelope and parses schedules', () async {
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.url.path, '/api/medications/');
      return http.Response(
        jsonEncode(_envelope('medications/list.json')),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repo = MedicationRepository(tokenStore: store, client: client);
    final meds = await repo.listMedications(access: _token);
    expect(meds, hasLength(1));
    expect(meds.first.name, 'Hydroxyurea');
    expect(meds.first.schedules.single.timeOfDay, '08:00:00');
  });

  test('logDose sends Idempotency-Key and parses event', () async {
    String? idemKey;
    final client = MockClient((request) async {
      idemKey = request.headers['Idempotency-Key'];
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['status'], 'TAKEN');
      expect(body['schedule'], 'sched-1');
      expect(body['taken_at'], isNotNull);
      return http.Response(
        jsonEncode(_envelope('log-dose.json')),
        201,
        headers: {'content-type': 'application/json'},
      );
    });
    final repo = MedicationRepository(tokenStore: store, client: client);
    final event = await repo.logDose(
      access: _token,
      medicationUid: 'med-1',
      scheduleUid: 'sched-1',
      status: 'TAKEN',
      takenAt: DateTime.utc(2026, 9, 16, 8, 5),
    );
    expect(idemKey, isNotNull);
    expect(idemKey, isNotEmpty);
    expect(event.status, 'TAKEN');
  });

  test('error envelope raises AuthException with code/status', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {
            'code': 'IDEMPOTENCY_CONFLICT',
            'message': 'Duplicate dose',
            'details': {},
          },
        }),
        409,
        headers: {'content-type': 'application/json'},
      );
    });
    final repo = MedicationRepository(tokenStore: store, client: client);
    await expectLater(
      repo.stopMedication(access: _token, uid: 'med-1'),
      throwsA(isA<AuthException>()
          .having((e) => e.statusCode, 'statusCode', 409)
          .having((e) => e.code, 'code', 'IDEMPOTENCY_CONFLICT')),
    );
  });

  test('fetchDashboard parses metrics and medical list', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(_envelope('dashboard.json')),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repo = HealthRepository(tokenStore: store, client: client);
    final dash = await repo.fetchDashboard(access: _token);
    expect(dash.activeMedCount, 1);
    expect(dash.dosesToday['taken'], 1);
    expect(dash.dosesToday['pending'], 1);
    expect(dash.adherenceLast7.adherencePct, 85.7);
    expect(dash.medicalList.single.dosesTodayPending, 1);
    expect(dash.recentSymptoms.single.painLevel, 8);
    expect(dash.recentTimeline.single.eventType, 'DOSE_LOGGED');
  });

  test('recordSymptom posts payload and parses response', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, contains('/symptoms/'));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['pain_level'], 6);
      expect(body['triggers'], isA<List>());
      return http.Response(
        jsonEncode({
          'data': {
            'uid': 'sym-2',
            'symptom_type_code': 'PAIN',
            'symptom_type_name': 'Pain',
            'pain_level': 6,
            'triggers': ['Stress'],
            'duration_minutes': 30,
            'notes': '',
            'recorded_at': '2026-09-16T07:30:00Z',
          }
        }),
        201,
        headers: {'content-type': 'application/json'},
      );
    });
    final repo = HealthRepository(tokenStore: store, client: client);
    final symptom = await repo.recordSymptom(
      access: _token,
      payload: {
        'symptom_type_code': 'PAIN',
        'pain_level': 6,
        'triggers': ['Stress'],
        'duration_minutes': 30,
        'recorded_at': '2026-09-16T07:30:00Z',
      },
    );
    expect(symptom.uid, 'sym-2');
    expect(symptom.painLevel, 6);
  });

  test('listSymptomTypes unwraps the flat catalog envelope', () async {
    // GET /api/symptom-types/ is explicitly unpaginated, so the renderer sends
    // `data` as a bare list rather than a `{results: …}` page.
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, contains('/symptom-types/'));
      return http.Response(
        jsonEncode({
          'data': [
            {'code': 'pain_crisis', 'name': 'Pain crisis', 'is_pain_related': true},
            {'code': 'headache', 'name': 'Headache', 'is_pain_related': false},
          ],
          'meta': {'correlation_id': ''},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repo = HealthRepository(tokenStore: store, client: client);
    final types = await repo.listSymptomTypes(access: _token);
    expect(types, hasLength(2));
    expect(types.first.code, 'pain_crisis');
    expect(types.first.isPainRelated, isTrue);
    expect(types.last.name, 'Headache');
  });

  test('listSymptoms still reads a paginated collection', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'data': {
            'count': 1,
            'next': null,
            'previous': null,
            'results': [
              {
                'uid': 'sym-1',
                'symptom_type_code': 'PAIN',
                'pain_level': 4,
                'triggers': [],
                'recorded_at': '2026-09-16T07:30:00Z',
              },
            ],
          },
          'meta': {'correlation_id': ''},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repo = HealthRepository(tokenStore: store, client: client);
    final symptoms = await repo.listSymptoms(access: _token);
    expect(symptoms, hasLength(1));
    expect(symptoms.single.painLevel, 4);
  });
}