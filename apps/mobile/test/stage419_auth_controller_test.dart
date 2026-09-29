import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/features/auth/data/auth_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/domain/auth_types.dart';
import 'package:sicklers_warriors/features/auth/presentation/controllers/auth_controller.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> _session() => {
      'access': 'access-1',
      'refresh': 'refresh-2',
      'user': {
        'email': 'warrior@example.com',
        'account_status': 'ACTIVE',
        'role_codes': ['PATIENT', 'BLOOD_DONOR'],
      },
    };

void main() {
  group('AuthController session lifecycle (Stage 4.19)', () {
    test('login persists the token pair and role claim from the server', () async {
      final store = EphemeralTokenStore();
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/login/');
        return _json({'data': _session()});
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );

      await controller.login(identifier: 'warrior@example.com', password: 'x');
      expect(controller.isAuthenticated, isTrue);
      expect(controller.email, 'warrior@example.com');
      expect(controller.roles, ['PATIENT', 'BLOOD_DONOR']);
      expect(await store.readAccess(), 'access-1');
      expect(await store.readRefresh(), 'refresh-2');
    });

    test('a 401 marks authError with the server message, no tokens stored',
        () async {
      final store = EphemeralTokenStore();
      final client = MockClient((request) async {
        return _json(
          {'error': {'code': 'INVALID_CREDENTIALS', 'message': 'Invalid credentials.'}},
          401,
        );
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await controller.login(identifier: 'x@example.com', password: 'nope');
      expect(controller.status, AuthStatus.authError);
      expect(controller.lastError?.code, 'INVALID_CREDENTIALS');
      expect(controller.lastError?.statusCode, 401);
      expect(await store.readAccess(), isNull);
    });

    test('restoreSession validates a stored token against /me', () async {
      final store = EphemeralTokenStore();
      await store.writeAccess('stored-access');

      // /me asserts the identity server-side; restore must NOT trust the raw
      // stored token alone (AUTH-2).
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/me/');
        expect(request.headers['Authorization'], 'Bearer stored-access');
        return _json({
          'data': {
            'email': 'warrior@example.com',
            'account_status': 'ACTIVE',
            'role_codes': ['PATIENT'],
          },
        });
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await controller.restoreSession();
      expect(controller.status, AuthStatus.authenticated);
      expect(controller.accessToken, 'stored-access');
      expect(controller.email, 'warrior@example.com');
      expect(controller.roles, ['PATIENT']);

      await store.clear();
      await controller.restoreSession();
      expect(controller.status, AuthStatus.unauthenticated);
    });

    test('restoreSession drops a stored token the server rejects (401)',
        () async {
      final store = EphemeralTokenStore();
      await store.writeAccess('stale-access');
      final client = MockClient((request) async {
        return _json(
          {'error': {'code': 'TOKEN_EXPIRED', 'message': 'Session expired.'}},
          401,
        );
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await controller.restoreSession();
      expect(controller.status, AuthStatus.unauthenticated);
      expect(controller.accessToken, isNull);
      expect(await store.readAccess(), isNull);
    });

    test('restoreSession with no stored token is unauthenticated', () async {
      final store = EphemeralTokenStore();
      final client = MockClient((_) async => _json({'data': {}}));
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await controller.restoreSession();
      expect(controller.status, AuthStatus.unauthenticated);
      expect(controller.accessToken, isNull);
    });

    test('refresh rotates the pair and persists the new ones', () async {
      final store = EphemeralTokenStore();
      await store.writeAccess('old-access');
      await store.writeRefresh('old-refresh');
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/login/') {
          return _json({'data': _session()});
        }
        if (request.url.path == '/api/auth/refresh/') {
          return _json({'data': {'access': 'new-access', 'refresh': 'new-refresh'}});
        }
        return http.Response('not found', 404);
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      // login() supplies the in-memory refresh token the rotation needs.
      await controller.login(identifier: 'warrior@example.com', password: 'x');
      expect(controller.accessToken, 'access-1');

      await controller.refreshSession();
      expect(controller.accessToken, 'new-access');
      expect(controller.refreshToken, 'new-refresh');
      expect(await store.readAccess(), 'new-access');
      expect(await store.readRefresh(), 'new-refresh');
    });

    test('a failed refresh transitions to tokenExpired (forces re-auth)', () async {
      final store = EphemeralTokenStore();
      await store.writeAccess('old-access');
      await store.writeRefresh('dead-refresh');
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/login/') {
          return _json({'data': _session()});
        }
        if (request.url.path == '/api/auth/refresh/') {
          return _json({'error': {'code': 'TOKEN_EXPIRED', 'message': 'Expired.'}}, 401);
        }
        return http.Response('not found', 404);
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await controller.login(identifier: 'warrior@example.com', password: 'x');
      expect(controller.status, AuthStatus.authenticated);

      await controller.refreshSession();
      expect(controller.status, AuthStatus.tokenExpired);
      expect(controller.lastError?.code, 'TOKEN_EXPIRED');
    });

    test('logout clears local state even when the server denies', () async {
      final store = EphemeralTokenStore();
      await store.writeAccess('access');
      await store.writeRefresh('refresh');
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/login/') {
          return _json({'data': _session()});
        }
        return _json({'error': {'code': 'DENIED', 'message': 'nope'}}, 500);
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );
      await controller.logout();
      expect(controller.status, AuthStatus.unauthenticated);
      expect(controller.accessToken, isNull);
      expect(await store.readAccess(), isNull);
      expect(await store.readRefresh(), isNull);
    });
  });

  group('me() session-expiry contract (Stage 4.19)', () {
    test('a 401 identity check yields the TOKEN_EXPIRED signal', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/me/');
        return _json({'error': {'code': 'TOKEN_EXPIRED', 'message': 'Session expired.'}}, 401);
      });
      final repo = AuthRepository(tokenStore: EphemeralTokenStore(), client: client);
      await expectLater(
        repo.me(access: 'expired'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', 'TOKEN_EXPIRED')
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });
}