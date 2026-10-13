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
}) =>
    {
      'uid': uid,
      'severity': 'URGENT',
      'type': 'MEDICAL',
      'description': 'Breathing difficulty',
      'location': {'text': 'Hostel B, room 4'},
      'status': status,
      'rate_limit_ok': true,
      'phone_verified': false,
      'responders': const [],
    };

/// A client that is offline until [online] flips, so tests can exercise the
/// failure → tap-retry → recovery path exactly once.
class _FlakyClient extends http.BaseClient {
  _FlakyClient({required this.online});

  bool online;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount += 1;
    if (!online) {
      throw http.ClientException('Network is unreachable', request.url);
    }
    final body = switch (request.url.path) {
      '/api/patients/me/' => {
          'data': {
            'emergency_contact_name': 'Ama',
            'emergency_contact_phone': '0244000000',
            'emergency_contact_relation': 'Sister',
          }
        },
      '/api/emergency/access-grants/' => {
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
        },
      '/api/emergency/requests/' => {
          'data': {'results': [_requestJson()]}
        },
      _ => {'data': {}},
    };
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('Offline behaviour (Stage 4.19)', () {
    test('a transport failure surfaces as an exception, never a silent success',
        () async {
      final client = _FlakyClient(online: false);
      final repo = EmergencyRepository(
        tokenStore: EphemeralTokenStore(),
        client: client,
      );
      await expectLater(
        repo.listRequests(access: _token),
        throwsA(isA<http.ClientException>()),
      );
    });

    testWidgets('a network failure shows the retry surface, and retry recovers',
        (tester) async {
      // The emergency home view is a long scroll (SOS trigger, request form,
      // dial card, access grants, active list); a tall viewport lays out the
      // whole surface so the assertions below are about state, not scrolling.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final client = _FlakyClient(online: false);
      await tester.pumpWidget(
        MaterialApp(
          home: EmergencyHomeView(
            accessToken: _token,
            repository: EmergencyRepository(
              tokenStore: EphemeralTokenStore(),
              client: client,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Offline: the retry action is offered instead of phantom data.
      expect(find.text(AppStrings.retry), findsOneWidget);
      expect(find.text('MEDICAL · URGENT'), findsNothing);
      final firstAttempt = client.requestCount;
      expect(firstAttempt, greaterThan(0));
      expect(find.text('MEDICAL · URGENT'), findsNothing);

      // Back online: one tap must reload from scratch. The retry surface sits
      // below the SOS trigger and the dial card, so bring it into view first.
      client.online = true;
      await tester.ensureVisible(find.text(AppStrings.retry).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.retry).last);
      await tester.pumpAndSettle();

      expect(find.text('MEDICAL · URGENT'), findsOneWidget);
      expect(find.text(AppStrings.retry), findsNothing);
      expect(client.requestCount, greaterThan(firstAttempt));
    });

    testWidgets('idempotency key is always attached to an SOS submit',
        (tester) async {
      String? sentKey;
      final client = MockClient((request) async {
        if (request.url.path == '/api/emergency/requests/') {
          sentKey = request.headers['Idempotency-Key'];
          return _json({'data': _requestJson(uid: 'emg-9')}, 201);
        }
        return http.Response('not found', 404);
      });
      final repo = EmergencyRepository(
        tokenStore: EphemeralTokenStore(),
        client: client,
      );
      await repo.createRequest(access: _token, type: 'MEDICAL');
      expect(sentKey, isNotNull);
      expect(sentKey, isNotEmpty);
    });
  });
}