import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/emergency/data/emergency_repository.dart';
import 'package:sicklers_warriors/features/emergency/presentation/pages/emergency_page.dart';

const _token = 'test-access';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> _requestJson({
  String uid = 'emg-1',
  String status = 'ACTIVE',
  Map<String, dynamic>? location,
  List<Map<String, dynamic>> responders = const [],
}) =>
    {
      'uid': uid,
      'severity': 'URGENT',
      'type': 'MEDICAL',
      'description': 'Breathing difficulty',
      'location': location,
      'status': status,
      'rate_limit_ok': true,
      'phone_verified': false,
      'responders': responders,
    };

const _responder = {
  'responder_role': 'STAFF',
  'status': 'ACKNOWLEDGED',
  'acknowledged_at': '2026-09-18T08:00:00Z',
};

void main() {
  group('EmergencyRepository (Stage 4.9)', () {
    test('getRequest parses responders + location and isActive', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/emergency/requests/emg-1/');
        return _json({
          'data': _requestJson(
            status: 'RESPONDING',
            location: {'text': 'Hostel B, room 4'},
            responders: [_responder],
          )
        });
      });
      final repo =
          EmergencyRepository(tokenStore: EphemeralTokenStore(), client: client);
      final detail = await repo.getRequest(access: _token, uid: 'emg-1');
      expect(detail.responders.single.role, 'STAFF');
      expect(detail.responders.single.status, 'ACKNOWLEDGED');
      expect(detail.locationLabel, 'Hostel B, room 4');
      expect(detail.isActive, isTrue);
      expect(detail.isResolved, isFalse);
    });

    test('validate posts to the action path', () async {
      final seen = <String>[];
      final client = MockClient((request) async {
        seen.add('${request.method} ${request.url.path}');
        return _json({
          'data': _requestJson(status: 'VALIDATING')
        });
      });
      final repo =
          EmergencyRepository(tokenStore: EphemeralTokenStore(), client: client);
      final validated = await repo.validate(access: _token, uid: 'emg-1');
      expect(validated.status, 'VALIDATING');
      expect(seen, ['POST /api/emergency/requests/emg-1/validate/']);
    });

    test('createRequest sends optional location', () async {
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({'data': _requestJson()}, 201);
      });
      final repo =
          EmergencyRepository(tokenStore: EphemeralTokenStore(), client: client);
      await repo.createRequest(
        access: _token,
        type: 'MEDICAL',
        location: {'text': 'Hostel B'},
      );
      expect(body!['location'], {'text': 'Hostel B'});
      expect(body!['idempotency_key'], isNotNull);
    });

    test('access grant scope is a JSON map and exposes active state', () async {
      final client = MockClient((request) async {
        return _json({
          'data': {
            'results': [
              {
                'uid': 'grant-1',
                'scope': {'patient_basics': true},
                'status': 'ACTIVE',
                'expires_at': '2026-09-19T08:00:00Z',
              },
            ],
          }
        });
      });
      final repo =
          EmergencyRepository(tokenStore: EphemeralTokenStore(), client: client);
      final grants = await repo.listAccessGrants(access: _token);
      expect(grants.single.scope['patient_basics'], isTrue);
      expect(grants.single.isActive, isTrue);
    });
  });

  group('Emergency SOS widgets (Stage 4.9)', () {
    MockClient client({bool failCreate = false}) => MockClient((request) async {
          if (request.url.path == '/api/patients/me/') {
            return _json({
              'data': {
                'emergency_contact_name': 'Ama Mensah',
                'emergency_contact_phone': '0244000000',
                'emergency_contact_relation': 'Sister',
              }
            });
          }
          if (request.url.path == '/api/emergency/access-grants/') {
            return _json({
              'data': {
                'results': [
                  {
                    'uid': 'grant-1',
                    'scope': {'patient_basics': true},
                    'status': 'ACTIVE',
                    'expires_at': '2026-09-19T08:00:00Z',
                  },
                ],
              }
            });
          }
          if (request.url.path == '/api/emergency/requests/') {
            if (request.method == 'POST') {
              if (failCreate) {
                return _json({'error': {'code': 'API_ERROR', 'message': 'x'}}, 503);
              }
              return _json({'data': _requestJson(uid: 'emg-2', status: 'RESOLVED')}, 201);
            }
            return _json({
              'data': {
                'results': [
                  _requestJson(
                    status: 'RESPONDING',
                    location: {'text': 'Hostel B'},
                    responders: [_responder],
                  ),
                ],
              }
            });
          }
          if (request.url.path == '/api/emergency/requests/emg-1/') {
            return _json({
              'data': _requestJson(
                status: 'RESPONDING',
                location: {'text': 'Hostel B'},
                responders: [_responder],
              )
            });
          }
          if (request.url.path == '/api/emergency/requests/emg-2/') {
            return _json({'data': _requestJson(uid: 'emg-2', status: 'RESOLVED')});
          }
          return http.Response('not found', 404);
        });

    Future<void> pumpPage(WidgetTester tester, {bool failCreate = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EmergencyHomeView(
            accessToken: _token,
            repository: EmergencyRepository(
              tokenStore: EphemeralTokenStore(),
              client: client(failCreate: failCreate),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> armSos(WidgetTester tester) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sos_hold'))),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('hold arms SOS and consent gates the confirmation sheet',
        (tester) async {
      await pumpPage(tester);
      expect(find.text(AppStrings.sosHoldToArm), findsOneWidget);
      await armSos(tester);
      expect(find.text(AppStrings.sosConfirmTitle), findsOneWidget);
      expect(find.text(AppStrings.sosConfirmBody), findsOneWidget);

      final sendFinder = find.descendant(
        of: find.byType(EmergencyConfirmSheet),
        matching: find.widgetWithText(FilledButton, AppStrings.submitEmergency),
      );
      expect(tester.widget<FilledButton>(sendFinder).onPressed, isNull);

      await tester.ensureVisible(find.text(AppStrings.sosShareConsent));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.sosShareConsent));
      await tester.pump();
      expect(tester.widget<FilledButton>(sendFinder).onPressed, isNotNull);

      await tester.ensureVisible(sendFinder);
      await tester.pumpAndSettle();
      await tester.tap(sendFinder);
      await tester.pumpAndSettle();
      // Created as RESOLVED so tracking shows EMG-005 with no residual red.
      expect(find.text(AppStrings.trackingResolvedTitle), findsOneWidget);
    });

    testWidgets('network failure never reports sent and tells user to call',
        (tester) async {
      await pumpPage(tester, failCreate: true);
      await armSos(tester);
      await tester.ensureVisible(find.text(AppStrings.sosShareConsent));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.sosShareConsent));
      await tester.pump();
      final sendFinder = find.descendant(
        of: find.byType(EmergencyConfirmSheet),
        matching: find.widgetWithText(FilledButton, AppStrings.submitEmergency),
      );
      await tester.ensureVisible(sendFinder);
      await tester.pumpAndSettle();
      await tester.tap(sendFinder);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.sosCallInstruction), findsOneWidget);
      expect(find.text(AppStrings.sosNotSentCallNow), findsOneWidget);
    });

    testWidgets('tapping a request opens tracking with responder timeline',
        (tester) async {
      await pumpPage(tester);
      expect(find.text('MEDICAL · URGENT'), findsOneWidget);
      await tester.tap(find.text('MEDICAL · URGENT'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.trackingTitle), findsOneWidget);
      expect(find.text('STAFF'), findsOneWidget);
      expect(find.text('ACKNOWLEDGED'), findsOneWidget);
      expect(find.text(AppStrings.trackingTimeline.toUpperCase()), findsOneWidget);
      // Dismiss to cancel the poll timer.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    });

    testWidgets('access grants surface to the patient', (tester) async {
      await pumpPage(tester);
      await tester.dragUntilVisible(
        find.textContaining(AppStrings.accessGrantedUntil),
        find.byType(ListView),
        const Offset(0, -120),
      );
      expect(find.textContaining(AppStrings.accessGrantedUntil), findsOneWidget);
    });
  });
}
