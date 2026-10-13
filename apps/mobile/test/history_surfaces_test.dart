/// Append-only history surface tests (blood decisions, doctor verification).
///
/// Run::
///   flutter test test/history_surfaces_test.dart
///
/// Both trails exist because the parent row only remembers the *latest* status.
/// These tests pin that a refusal and the reason for it stay readable, and that
/// neither screen invents a row the API did not send.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/domain/auth_types.dart';
import 'package:sicklers_warriors/features/blood_donation/data/blood_repository.dart';
import 'package:sicklers_warriors/features/blood_donation/presentation/pages/blood_decision_history_page.dart';
import 'package:sicklers_warriors/features/doctor_network/data/doctor_directory_repository.dart';
import 'package:sicklers_warriors/features/doctor_network/presentation/pages/doctor_verification_history_page.dart';

const _token = 'test-access';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: materialLocalizationsDelegates(
        LocaleController(AppPreferences.memory()),
      ),
      supportedLocales: AppLocalizationsDelegate.supportedLocales,
      theme: ThemeData(useMaterial3: true),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Blood decision trail', () {
    BloodRepository bloodRepository(http.Client client) =>
        BloodRepository(tokenStore: EphemeralTokenStore(), client: client);

    test('a rejection keeps the decider, the reason and the transition',
        () async {
      final client = MockClient((request) async => _json([
            {
              'uid': 'd1',
              'request_uid': 'r1',
              'decision': 'REJECTED',
              'from_status': 'PENDING_VERIFICATION',
              'to_status': 'REJECTED',
              'reason': 'No matching donor was registered for O- at Korle Bu.',
              'actor_name': 'Ama Owusu',
              'decided_at': '2099-01-02T09:00:00Z',
            },
          ]));

      final decisions = await bloodRepository(client)
          .listDecisions(access: _token, requestUid: 'r1');

      expect(decisions, hasLength(1));
      expect(decisions.single.isRejection, isTrue);
      expect(decisions.single.transition, 'PENDING_VERIFICATION → REJECTED');
      expect(decisions.single.reason, startsWith('No matching donor'));
      expect(decisions.single.actorName, 'Ama Owusu');
    });

    test('the endpoint answers a bare list, not a paginated envelope',
        () async {
      // Regression guard: this route returns `[{...}]` while most others return
      // `{results: [...]}`. Parsing it as an envelope silently yields nothing.
      final client = MockClient((request) async => _json([
            {'uid': 'd1', 'decision': 'SUBMITTED', 'to_status': 'SUBMITTED'},
          ]));

      final decisions =
          await bloodRepository(client).listDecisions(access: _token, requestUid: 'r1');
      expect(decisions, hasLength(1));
    });

    testWidgets('the screen shows the reason and offers a retry',
        (tester) async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts == 1) return _json({'detail': 'Service unavailable.'}, 503);
        return _json([
          {
            'uid': 'd1',
            'decision': 'REJECTED',
            'from_status': 'PENDING_VERIFICATION',
            'to_status': 'REJECTED',
            'reason': 'Stock wastage reported for O- at the centre.',
            'actor_name': 'Ama Owusu',
            'decided_at': '2099-01-02T09:00:00Z',
          },
        ]);
      });

      await _pump(
        tester,
        BloodDecisionHistoryPage(
          accessToken: _token,
          repository: bloodRepository(client),
          requestUid: 'r1',
        ),
      );
      // The server's own message is shown rather than a generic one.
      expect(find.text('Service unavailable.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('PENDING_VERIFICATION → REJECTED'), findsOneWidget);
      expect(find.textContaining('Stock wastage reported'), findsOneWidget);
      expect(find.textContaining('Ama Owusu'), findsOneWidget);
    });

    testWidgets('no decisions reads as an honest empty state', (tester) async {
      await _pump(
        tester,
        BloodDecisionHistoryPage(
          accessToken: _token,
          repository: bloodRepository(MockClient((_) async => _json(const <dynamic>[]))),
          requestUid: 'r1',
        ),
      );

      expect(
        find.text('No decisions have been recorded for this request yet.'),
        findsOneWidget,
      );
    });
  });

  group('Doctor verification trail', () {
    DoctorDirectoryRepository directory(http.Client client) =>
        DoctorDirectoryRepository(
          tokenStore: EphemeralTokenStore(),
          client: client,
        );

    test('reads the envelope the history route returns', () async {
      final client = MockClient((request) async => _json({
            'doctor_uid': 'u1',
            'verification_status': 'APPROVED',
            'count': 2,
            'decisions': [
              {
                'uid': 'd2',
                'decision': 'APPROVED',
                'from_status': 'PENDING_VERIFICATION',
                'to_status': 'APPROVED',
                'reason': '',
                'actor_name': 'Review Officer',
                'license_number': 'GMC-1234',
                'decided_at': '2099-02-01T10:00:00Z',
              },
              {
                'uid': 'd1',
                'decision': 'REJECTED',
                'from_status': 'PENDING_VERIFICATION',
                'to_status': 'REJECTED',
                'reason': 'Registration number did not match the council register.',
                'actor_name': 'Review Officer',
                'license_number': 'GMC-1234',
                'decided_at': '2099-01-20T08:00:00Z',
              },
            ],
          }));

      final history =
          await directory(client).verificationHistory(access: _token, uid: 'u1');

      expect(history.verificationStatus, 'APPROVED');
      expect(history.decisions, hasLength(2));
      expect(history.decisions.first.isRejection, isFalse);
      expect(history.decisions.last.isRejection, isTrue);
    });

    testWidgets('the earlier rejection is still readable', (tester) async {
      final client = MockClient((request) async => _json({
            'doctor_uid': 'u1',
            'verification_status': 'APPROVED',
            'decisions': [
              {
                'uid': 'd1',
                'decision': 'REJECTED',
                'from_status': 'PENDING_VERIFICATION',
                'to_status': 'REJECTED',
                'reason': 'Registration number did not match the register.',
                'actor_name': 'Review Officer',
                'decided_at': '2099-01-20T08:00:00Z',
              },
            ],
          }));

      await _pump(
        tester,
        DoctorVerificationHistoryPage(
          accessToken: _token,
          repository: directory(client),
          doctorUid: 'u1',
          displayName: 'Dr. Mensah',
        ),
      );

      expect(find.text('Dr. Mensah'), findsOneWidget);
      expect(find.text('APPROVED'), findsOneWidget);
      expect(find.text('PENDING_VERIFICATION → REJECTED'), findsOneWidget);
      expect(
        find.text('Registration number did not match the register.'),
        findsOneWidget,
      );
    });

    testWidgets('a 404 for a non-reviewer is the server message', (tester) async {
      final client = MockClient((request) async => _json({
            'error': {
              'code': 'NOT_FOUND',
              'message': 'Verification history not found.',
            }
          }, 404));

      await _pump(
        tester,
        DoctorVerificationHistoryPage(
          accessToken: _token,
          repository: directory(client),
          doctorUid: 'u1',
        ),
      );

      // The route answers 404 rather than 403 so it never confirms that a
      // licence application exists; that message is what the reader sees.
      expect(find.text('Verification history not found.'), findsOneWidget);
      expect(
        find.text('The verification history could not be loaded.'),
        findsNothing,
      );
    });

    testWidgets('no decisions reads as an honest empty state', (tester) async {
      final client = MockClient((request) async => _json({
            'doctor_uid': 'u1',
            'verification_status': 'PENDING',
            'decisions': const <dynamic>[],
          }));

      await _pump(
        tester,
        DoctorVerificationHistoryPage(
          accessToken: _token,
          repository: directory(client),
          doctorUid: 'u1',
        ),
      );

      expect(
        find.text('No verification decisions have been recorded yet.'),
        findsOneWidget,
      );
    });
  });

  group('Authorization errors are not swallowed', () {
    testWidgets('an expired session surfaces the token message', (tester) async {
      final client = MockClient((request) async => _json({
            'error': {
              'code': 'TOKEN_EXPIRED',
              'message': 'Session expired. Please sign in again.',
            }
          }, 401));

      await _pump(
        tester,
        BloodDecisionHistoryPage(
          accessToken: 'expired',
          repository: BloodRepository(
            tokenStore: EphemeralTokenStore(),
            client: client,
          ),
          requestUid: 'r1',
        ),
      );

      expect(find.text('Session expired. Please sign in again.'), findsOneWidget);
    });

    test('an AuthException keeps the code the server sent', () async {
      final client = MockClient((request) async => _json({
            'error': {'code': 'PERMISSION_DENIED', 'message': 'Not available.'}
          }, 403));

      await expectLater(
        DoctorDirectoryRepository(
          tokenStore: EphemeralTokenStore(),
          client: client,
        ).verificationHistory(access: _token, uid: 'u1'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.code, 'code', 'PERMISSION_DENIED')
              .having((e) => e.message, 'message', 'Not available.'),
        ),
      );
    });
  });
}