import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/blood_donation/data/blood_repository.dart';
import 'package:sicklers_warriors/features/blood_donation/presentation/pages/blood_donation_page.dart';
import 'package:sicklers_warriors/features/emergency/data/emergency_repository.dart';
import 'package:sicklers_warriors/features/emergency/presentation/pages/emergency_page.dart';
import 'package:sicklers_warriors/features/notifications/data/notifications_repository.dart';
import 'package:sicklers_warriors/features/notifications/presentation/pages/notifications_page.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

MockClient _bloodClient() => MockClient((request) async {
      if (request.url.path == '/api/blood/donors/me/') {
        return _json({
          'error': {'code': 'NOT_FOUND', 'message': 'None'}
        }, 404);
      }
      if (request.url.path == '/api/blood/requests/') {
        return _json({
          'data': {
            'results': [
              {
                'uid': 'req-1',
                'blood_group_needed': 'O-',
                'units': 2,
                'urgency': 'URGENT',
                'status': 'ACTIVE',
                'reason': 'Surgery',
                'location': 'Ward 4',
                'facility': {'uid': 'fac-1', 'name': 'Gate General Hospital'},
              },
            ],
          }
        });
      }
      return http.Response('not found', 404);
    });

MockClient _emergencyClient() => MockClient((request) async {
      if (request.url.path == '/api/emergency/requests/') {
        return _json({
          'data': {
            'results': [
              {
                'uid': 'emg-1',
                'severity': 'URGENT',
                'type': 'MEDICAL',
                'description': 'Breathing difficulty',
                'location': null,
                'status': 'ACTIVE',
                'rate_limit_ok': true,
                'phone_verified': false,
              },
            ],
          }
        });
      }
      return http.Response('not found', 404);
    });

MockClient _notificationsClient() => MockClient((request) async {
      if (request.url.path == '/api/notifications/preferences/') {
        return _json({
          'data': {
            'preferences': {'BLOOD': true, 'COMMUNITY': false}
          }
        });
      }
      if (request.url.path == '/api/notifications/') {
        return _json({
          'data': {
            'results': [
              {
                'id': 1,
                'type': 'BLOOD',
                'channel': 'IN_APP',
                'title': 'Match found',
                'body': 'A donor accepted your request',
                'status': 'PENDING',
              },
            ],
          }
        });
      }
      return http.Response('not found', 404);
    });

void main() {
  testWidgets('BloodDonationPage guards when signed out', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BloodDonationPage()));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.notSignedIn), findsOneWidget);
  });

  testWidgets('EmergencyPage guards when signed out', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EmergencyPage()));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.notSignedIn), findsOneWidget);
  });

  testWidgets('NotificationsPage guards when signed out', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.notSignedIn), findsOneWidget);
  });

  testWidgets('BloodHomeView loads requests', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BloodHomeView(
          accessToken: 'test-access',
          repository: BloodRepository(
            tokenStore: EphemeralTokenStore(),
            client: _bloodClient(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('units'), findsOneWidget);
    expect(find.text(AppStrings.becomeDonor), findsOneWidget);
  });

  testWidgets('EmergencyHomeView loads active emergencies', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EmergencyHomeView(
          accessToken: 'test-access',
          repository: EmergencyRepository(
            tokenStore: EphemeralTokenStore(),
            client: _emergencyClient(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.triggerEmergency), findsOneWidget);
    expect(find.text('MEDICAL · URGENT'), findsOneWidget);
    expect(find.text('Breathing difficulty'), findsOneWidget);
  });

  testWidgets('NotificationsHomeView lists inbox and preferences',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsHomeView(
          accessToken: 'test-access',
          repository: NotificationsRepository(
            tokenStore: EphemeralTokenStore(),
            client: _notificationsClient(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Match found'), findsOneWidget);

    await tester.tap(find.text(AppStrings.preferences));
    await tester.pumpAndSettle();
    expect(find.text('Blood network & donors'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsWidgets);
  });
}
