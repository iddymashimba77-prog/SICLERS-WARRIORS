import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/features/auth/data/auth_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/presentation/controllers/auth_controller.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// What the backend `POST /auth/register/` returns on success.
Map<String, dynamic> _registerPayload({
  bool withTokens = true,
  bool verificationRequired = false,
}) =>
    {
      if (withTokens) 'access': 'new-access',
      if (withTokens) 'refresh': 'new-refresh',
      'user': {
        'email': 'newbie@example.com',
        'account_status': 'ACTIVE',
        'has_login_pin': false,
      },
      'verification_required': verificationRequired,
    };

void main() {
  group('Registration establishes a real session (regression)', () {
    test('the issued token pair is persisted, not discarded', () async {
      final store = EphemeralTokenStore();
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/register/');
        return _json(_registerPayload(), 201);
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );

      await controller.register(email: 'newbie@example.com', password: 'Str0ng!Pass9');

      expect(controller.isAuthenticated, isTrue,
          reason: 'the server issues a usable session at registration');
      expect(await store.readAccess(), 'new-access');
      expect(await store.readRefresh(), 'new-refresh');
      expect(controller.lastError, isNull);
    });

    test('a response without tokens leaves the account unauthenticated',
        () async {
      final store = EphemeralTokenStore();
      final client = MockClient((request) async => _json(
            _registerPayload(withTokens: false, verificationRequired: true),
            201,
          ));
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );

      await controller.register(email: 'newbie@example.com', password: 'Str0ng!Pass9');

      expect(controller.isAuthenticated, isFalse);
      expect(await store.readAccess(), isNull);
      // No token pair and no error: the UI falls back to the sign-in screen.
      expect(controller.lastError, isNull);
    });

    test('a stale failure from a previous attempt is cleared on success', () async {
      final store = EphemeralTokenStore();
      var attempt = 0;
      final client = MockClient((request) async {
        attempt++;
        if (attempt == 1) {
          return _json(
            {'error': {'code': 'EMAIL_EXISTS', 'message': 'That email is already registered.'}},
            409,
          );
        }
        return _json(_registerPayload(), 201);
      });
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );

      await controller.register(email: 'newbie@example.com', password: 'Str0ng!Pass9');
      expect(controller.lastError, isNotNull, reason: 'first attempt failed');

      await controller.register(email: 'newbie@example.com', password: 'Str0ng!Pass9');
      expect(controller.lastError, isNull,
          reason: 'the old error must not survive a successful sign-up');
      expect(controller.isAuthenticated, isTrue);
    });

    test('a duplicate registration still surfaces the server message', () async {
      final store = EphemeralTokenStore();
      final client = MockClient((request) async => _json(
            {'error': {'code': 'EMAIL_EXISTS', 'message': 'That email is already registered.'}},
            409,
          ));
      final controller = AuthController(
        repository: AuthRepository(tokenStore: store, client: client),
      );

      await controller.register(email: 'newbie@example.com', password: 'Str0ng!Pass9');

      expect(controller.lastError?.message, 'That email is already registered.');
      expect(controller.isAuthenticated, isFalse);
      expect(await store.readAccess(), isNull);
    });
  });
}