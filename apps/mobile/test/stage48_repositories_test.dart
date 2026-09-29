import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/domain/auth_types.dart';
import 'package:sicklers_warriors/features/blood_donation/data/blood_repository.dart';
import 'package:sicklers_warriors/features/emergency/data/emergency_repository.dart';
import 'package:sicklers_warriors/features/notifications/data/notifications_repository.dart';

const _token = 'test-access';

Map<String, dynamic> _requestJson({String status = 'ACTIVE'}) => {
      'uid': 'req-1',
      'blood_group_needed': 'O-',
      'units': 2,
      'urgency': 'URGENT',
      'status': status,
      'reason': 'Surgery',
      'location': 'Ward 4',
      'facility': {'uid': 'fac-1', 'name': 'Gate General Hospital'},
      'created_at': '2026-09-18T08:00:00Z',
    };

void main() {
  final store = EphemeralTokenStore();

  group('BloodRepository', () {
    test('listRequests unwraps envelope and parses facility', () async {
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer $_token');
        expect(request.url.path, '/api/blood/requests/');
        return http.Response(
          jsonEncode({
            'data': {
              'results': [_requestJson()],
            },
            'meta': {'count': 1},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = BloodRepository(tokenStore: store, client: client);
      final requests = await repo.listRequests(access: _token);
      expect(requests, hasLength(1));
      expect(requests.first.bloodGroupNeeded, 'O-');
      expect(requests.first.facilityName, 'Gate General Hospital');
      expect(requests.first.isOpen, isTrue);
    });

    test('createRequest sends Idempotency-Key and body', () async {
      String? idem;
      final client = MockClient((request) async {
        idem = request.headers['Idempotency-Key'];
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['blood_group_needed'], 'O-');
        expect(body['units'], 2);
        expect(body['urgency'], 'URGENT');
        return http.Response(
          jsonEncode({'data': _requestJson()}),
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = BloodRepository(tokenStore: store, client: client);
      final created = await repo.createRequest(
        access: _token,
        bloodGroupNeeded: 'O-',
        units: 2,
        urgency: 'URGENT',
        reason: 'Surgery',
      );
      expect(idem, isNotNull);
      expect(idem, isNotEmpty);
      expect(created.uid, 'req-1');
    });

    test('respondToMatch posts ACCEPT action', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/blood/matches/7/respond/');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['action'], 'ACCEPT');
        return http.Response(
          jsonEncode({
            'data': {
              'id': 7,
              'request_uid': 'req-1',
              'donor': {'id': 3, 'blood_group': 'O-'},
              'match_score': 0.75,
              'match_reason': 'compatible',
              'status': 'ACCEPTED',
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = BloodRepository(tokenStore: store, client: client);
      final match = await repo.respondToMatch(
        access: _token,
        matchId: 7,
        accept: true,
      );
      expect(match.status, 'ACCEPTED');
    });

    test('getDonorProfile returns null when the profile is absent', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'NOT_FOUND', 'message': 'None'}
          }),
          404,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = BloodRepository(tokenStore: store, client: client);
      final profile = await repo.getDonorProfile(access: _token);
      expect(profile, isNull);
    });
  });

  group('EmergencyRepository', () {
    test('createRequest sends idempotency key and parses status', () async {
      String? idem;
      final client = MockClient((request) async {
        idem = request.headers['Idempotency-Key'];
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['type'], 'PAIN_CRISIS');
        expect(body['severity'], 'CRITICAL');
        return http.Response(
          jsonEncode({
            'data': {
              'uid': 'emg-1',
              'severity': 'CRITICAL',
              'type': 'PAIN_CRISIS',
              'description': 'Severe pain',
              'location': null,
              'status': 'CREATED',
              'rate_limit_ok': true,
              'phone_verified': false,
            }
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = EmergencyRepository(tokenStore: store, client: client);
      final emergency = await repo.createRequest(
        access: _token,
        type: 'PAIN_CRISIS',
        severity: 'CRITICAL',
        description: 'Severe pain',
      );
      expect(idem, isNotNull);
      expect(emergency.status, 'CREATED');
      expect(emergency.isActive, isTrue);
    });

    test('respond/escalate/resolve/cancel hit the right action paths', () async {
      final seen = <String>[];
      final client = MockClient((request) async {
        seen.add(request.url.path);
        return http.Response(
          jsonEncode({
            'data': {
              'uid': 'emg-1',
              'severity': 'URGENT',
              'type': 'MEDICAL',
              'description': '',
              'location': null,
              'status': 'RESPONDING',
              'rate_limit_ok': true,
              'phone_verified': false,
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = EmergencyRepository(tokenStore: store, client: client);
      await repo.respond(access: _token, uid: 'emg-1');
      await repo.escalate(access: _token, uid: 'emg-1');
      await repo.resolve(access: _token, uid: 'emg-1');
      await repo.cancel(access: _token, uid: 'emg-1');
      expect(seen, [
        '/api/emergency/requests/emg-1/respond/',
        '/api/emergency/requests/emg-1/escalate/',
        '/api/emergency/requests/emg-1/resolve/',
        '/api/emergency/requests/emg-1/cancel/',
      ]);
    });

    test('error envelope raises AuthException with status', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'code': 'IDEMPOTENCY_CONFLICT', 'message': 'Duplicate'}
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = EmergencyRepository(tokenStore: store, client: client);
      await expectLater(
        repo.createRequest(access: _token, type: 'MEDICAL'),
        throwsA(isA<AuthException>().having((e) => e.statusCode, 'status', 409)),
      );
    });
  });

  group('NotificationsRepository', () {
    test('list parses recipient notifications', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/notifications/');
        return http.Response(
          jsonEncode({
            'data': {
              'results': [
                {
                  'id': 1,
                  'type': 'BLOOD',
                  'channel': 'IN_APP',
                  'title': 'Match found',
                  'body': 'A donor accepted',
                  'status': 'PENDING',
                },
              ],
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = NotificationsRepository(tokenStore: store, client: client);
      final items = await repo.list(access: _token);
      expect(items.single.title, 'Match found');
      expect(items.single.isUnread, isTrue);
    });

    test('readAll returns updated count', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/notifications/read-all/');
        return http.Response(
          jsonEncode({
            'data': {'updated': 3}
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = NotificationsRepository(tokenStore: store, client: client);
      expect(await repo.readAll(access: _token), 3);
    });

    test('getPreferences and updatePreference use the preferences route', () async {
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'data': {
                'preferences': {'BLOOD': true, 'COMMUNITY': false}
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        expect(request.url.path, '/api/notifications/preferences/');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['category'], 'COMMUNITY');
        expect(body['enabled'], isTrue);
        return http.Response(
          jsonEncode({
            'data': {'category': 'COMMUNITY', 'enabled': true}
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = NotificationsRepository(tokenStore: store, client: client);
      final prefs = await repo.getPreferences(access: _token);
      expect(prefs['COMMUNITY'], isFalse);
      await repo.updatePreference(
        access: _token,
        category: 'COMMUNITY',
        enabled: true,
      );
    });
  });
}
