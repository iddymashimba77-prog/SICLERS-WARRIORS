// Stage 4.30 — ADMIN-3 portal: repository wire-format + dashboard widgets.
//
// The repository mirrors the backend admin endpoint matrix; these tests pin
// the request shapes (method, path, body, query filters) and the envelope
// unwrapping so the portal keeps talking to the real API, not a fiction.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/features/admin/data/admin_repository.dart';
import 'package:sicklers_warriors/features/admin/presentation/pages/admin_dashboard_page.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/domain/auth_types.dart';

const _token = 'test-access';

TokenStore _store() => EphemeralTokenStore();

Map<String, dynamic> _userRow(String uid, {String status = 'ACTIVE'}) => {
      'uid': uid,
      'email': 'user@example.com',
      'phone': '+255700000000',
      'full_name': 'Test User',
      'account_status': status,
      'role_codes': ['PATIENT'],
      'mfa_enabled': false,
      'created_at': '2026-09-01T09:00:00Z',
    };

AdminRepository _repo(MockClient client) =>
    AdminRepository(tokenStore: _store(), client: client);

void main() {
  group('AdminRepository wire contract', () {
    test('listUsers unwraps paginated results and sends filters', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/admin/users/');
        expect(request.url.queryParameters['status'], 'ACTIVE');
        expect(request.url.queryParameters['q'], 'asante');
        return http.Response(
          jsonEncode({
            'data': {
              'count': 1,
              'next': null,
              'previous': null,
              'results': [_userRow('u-1')],
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final users = await _repo(client)
          .listUsers(access: _token, status: 'ACTIVE', query: 'asante');
      expect(users, hasLength(1));
      expect(users.single.uid, 'u-1');
      expect(users.single.isActive, isTrue);
      expect(users.single.roleCodes, ['PATIENT']);
    });

    test('setUserStatus posts reason to activate/deactivate path', () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        expect(jsonDecode(request.body), {'reason': 'policy'});
        return http.Response(
          jsonEncode({'data': _userRow('u-1')}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await _repo(client).setUserStatus(
        access: _token,
        uid: 'u-1',
        activate: true,
        reason: 'policy',
      );
      await _repo(client).setUserStatus(
        access: _token,
        uid: 'u-1',
        activate: false,
        reason: 'policy',
      );
      expect(requests,
          ['POST /api/admin/users/u-1/activate/', 'POST /api/admin/users/u-1/deactivate/']);
    });

    test('changeUserRole grants by POST and revokes by DELETE', () async {
      final seen = <String>[];
      final client = MockClient((request) async {
        seen.add(request.method);
        expect(request.url.path, '/api/admin/users/u-1/roles/');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['role_code'], 'HEALTH_PROFESSIONAL');
        expect(body['reason'], 'promotion');
        return http.Response(
          jsonEncode({'data': _userRow('u-1')}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await _repo(client).changeUserRole(
        access: _token,
        uid: 'u-1',
        roleCode: 'HEALTH_PROFESSIONAL',
        grant: true,
        reason: 'promotion',
      );
      await _repo(client).changeUserRole(
        access: _token,
        uid: 'u-1',
        roleCode: 'HEALTH_PROFESSIONAL',
        grant: false,
        reason: 'promotion',
      );
      expect(seen, ['POST', 'DELETE']);
    });

    test('verifyFacility skips the trailing slash the backend rejects', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/admin/facilities/f-1/verify');
        expect(request.url.path, endsWith('verify'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['approve'], isTrue);
        return http.Response(
          jsonEncode({'data': {'uid': 'f-1'}}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await _repo(client).verifyFacility(
        access: _token,
        uid: 'f-1',
        approve: true,
        reason: 'documents ok',
      );
    });

    test('listAuditLogs forwards every supported filter', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/admin/audit-logs/');
        expect(request.url.queryParameters['action_code'], 'USER_MANAGE_DEACTIVATE');
        expect(request.url.queryParameters['resource_type'], 'USER');
        expect(request.url.queryParameters['result'], 'FAILURE');
        expect(request.url.queryParameters['actor'], 'admin@example.com');
        expect(request.url.queryParameters['date_from'], '2026-09-01');
        return http.Response(
          jsonEncode({
            'data': {
              'count': 1,
              'results': [
                {
                  'id': 1,
                  'actor_email': 'admin@example.com',
                  'action_code': 'USER_MANAGE_DEACTIVATE',
                  'resource_type': 'USER',
                  'resource_id': 'u-1',
                  'result': 'FAILURE',
                  'ip_address': '127.0.0.1',
                  'request_id': 'req-1',
                  'created_at': '2026-09-10T08:00:00Z',
                }
              ],
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final logs = await _repo(client).listAuditLogs(
        access: _token,
        actionCode: 'USER_MANAGE_DEACTIVATE',
        resourceType: 'USER',
        result: 'FAILURE',
        actor: 'admin@example.com',
        dateFrom: '2026-09-01',
      );
      expect(logs.single.actionCode, 'USER_MANAGE_DEACTIVATE');
      expect(logs.single.result, 'FAILURE');
      expect(logs.single.requestId, 'req-1');
    });

    test('listSecurityEvents parses nested user and sends filters', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['event_type'], 'LOGIN_FAILED');
        expect(request.url.queryParameters['status'], 'OPEN');
        return http.Response(
          jsonEncode({
            'data': {
              'results': [
                {
                  'id': 9,
                  'user': {'uid': 'u-1', 'email': 'user@example.com'},
                  'event_type': 'LOGIN_FAILED',
                  'status': 'OPEN',
                  'ip_address': '10.0.0.1',
                  'user_agent': 'test',
                  'detail': {'attempts': 3},
                  'created_at': '2026-09-10T08:00:00Z',
                }
              ],
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final events = await _repo(client).listSecurityEvents(
        access: _token,
        eventType: 'LOGIN_FAILED',
        status: 'OPEN',
      );
      expect(events.single.eventType, 'LOGIN_FAILED');
      expect(events.single.userEmail, 'user@example.com');
      expect(events.single.detail['attempts'], 3);
    });

    test('setRolePermission posts grant decision and returns new codes', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/admin/roles/ADMIN/permissions/');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['permission_code'], 'doctors.verify');
        expect(body['grant'], isTrue);
        expect(body['reason'], 'ops');
        return http.Response(
          jsonEncode({
            'data': {'permission_codes': ['doctors.verify']},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final codes = await _repo(client).setRolePermission(
        access: _token,
        roleCode: 'ADMIN',
        permissionCode: 'doctors.verify',
        grant: true,
        reason: 'ops',
      );
      expect(codes, ['doctors.verify']);
    });

    test('broadcast sends audience matrices incl. user_uid array', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/admin/notifications/broadcast/');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['audience'], 'USERS');
        expect(body['title'], 'Update');
        expect(body['body'], 'Please read');
        expect(body['user_uid'], ['u-1', 'u-2']);
        return http.Response(
          jsonEncode({
            'data': {'audience': 'USERS', 'recipient_count': 2},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final result = await _repo(client).broadcast(
        access: _token,
        audience: 'USERS',
        title: 'Update',
        body: 'Please read',
        userUids: ['u-1', 'u-2'],
      );
      expect(result.audience, 'USERS');
      expect(result.recipientCount, 2);
    });

    test('getUserRoles returns the role list from the payload', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/admin/users/u-1/roles/');
        return http.Response(
          jsonEncode({'data': {'uid': 'u-1', 'roles': ['PATIENT', 'DONOR']}}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final roles = await _repo(client).getUserRoles(access: _token, uid: 'u-1');
      expect(roles, ['PATIENT', 'DONOR']);
    });

    test('error envelope surfaces code and status for the portal', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'PERMISSION_DENIED',
              'message': 'Not permitted',
              'details': {},
            },
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });
      await expectLater(
        _repo(client).listUsers(access: _token),
        throwsA(isA<AuthException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.code, 'code', 'PERMISSION_DENIED')),
      );
    });
  });

  group('AdminDashboardPage widgets', () {
    testWidgets('loads real KPIs from the dashboard endpoint', (tester) async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/admin/dashboard/');
        return http.Response(
          jsonEncode({
            'data': {
              'generated_at': '2026-09-16T09:00:00Z',
              'role_kernel': 'admin.kpis.dashboard.admins',
              'kpis': {
                'users_total': 42,
                'users_active_patients': 3,
                'verified_docs': 2,
                'active_blood_requests': 1,
                'emergency_requests_critical': 0,
                'active_campaigns': 4,
                'confirmed_donations_amount': '125000.00',
                'open_reports': 6,
              },
              'trends': {},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdminDashboardPage(
            repository: _repo(client),
            accessToken: _token,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Platform Dashboard · admin.kpis.dashboard.admins'),
          findsOneWidget);
      expect(find.text('Total Users'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('125000 TZS'), findsOneWidget);
    });

    testWidgets('renders the retry view when the dashboard request fails',
        (tester) async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'API_ERROR',
              'message': 'boom',
              'details': {},
            },
          }),
          500,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdminDashboardPage(
            repository: _repo(client),
            accessToken: _token,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('The dashboard could not be loaded.'), findsOneWidget);
    });
  });
}