import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/community/presentation/pages/community_page.dart';
import 'package:sicklers_warriors/features/medication/presentation/pages/medication_page.dart';
import 'package:sicklers_warriors/features/notifications/data/notifications_repository.dart';
import 'package:sicklers_warriors/features/notifications/presentation/pages/notifications_page.dart';

const _token = 'test-access';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> _notificationJson({
  int id = 1,
  String type = 'SYSTEM',
  String status = 'PENDING',
  String priority = 'HIGH',
  String? route,
}) =>
    {
      'id': id,
      'type': type,
      'channel': 'IN_APP',
      'title': 'T$id',
      'body': 'B$id',
      'status': status,
      'priority': priority,
      if (route != null) 'data': {'route': route},
    };

void main() {
  final store = EphemeralTokenStore();

  group('AppNotification', () {
    test('parses priority, data route and derived flags', () {
      final n = AppNotification.fromJson(_notificationJson(
        type: 'EMERGENCY',
        priority: 'CRITICAL',
        route: 'emergency',
      ));
      expect(n.priority, 'CRITICAL');
      expect(n.isCritical, isTrue);
      expect(n.isEmergency, isTrue);
      expect(n.route, 'emergency');
      expect(n.isUnread, isTrue);
    });

    test('low priority is not critical', () {
      final n = AppNotification.fromJson(
        _notificationJson(type: 'SYSTEM', priority: 'LOW'),
      );
      expect(n.isCritical, isFalse);
      expect(n.isHighPriority, isFalse);
      expect(n.route, isNull);
    });
  });

  group('NotificationsRepository (Stage 4.13)', () {
    test('unreadCount reads the unread-count endpoint', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/notifications/unread-count/');
        return _json({
          'data': {'unread': 3}
        });
      });
      final repo = NotificationsRepository(tokenStore: store, client: client);
      expect(await repo.unreadCount(access: _token), 3);
    });

    test('registerDevice posts the token and never echoes it back', () async {
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        expect(request.url.path, '/api/notifications/devices/');
        expect(request.method, 'POST');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        expect(sent['push_token'], 'fcm-token-private');
        return _json({
          'data': {
            'id': 7,
            'platform': 'ANDROID',
            'device_id': 'D1',
            'is_active': true,
            'last_seen_at': '2026-09-23T10:00:00Z',
          }
        }, 201);
      });
      final repo = NotificationsRepository(tokenStore: store, client: client);
      final device = await repo.registerDevice(
        access: _token,
        pushToken: 'fcm-token-private',
        platform: 'ANDROID',
        deviceId: 'D1',
      );
      expect(sent.containsKey('push_token'), isTrue);
      expect(device.id, 7);
      expect(device.platform, 'ANDROID');
      expect(device.isActive, isTrue);
    });

    test('listDevices parses a list envelope', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/notifications/devices/');
        return _json({
          'data': [
            {'id': 1, 'platform': 'ANDROID', 'device_id': 'D1', 'is_active': true},
            {'id': 2, 'platform': 'IOS', 'device_id': 'D2', 'is_active': false},
          ]
        });
      });
      final repo = NotificationsRepository(tokenStore: store, client: client);
      final devices = await repo.listDevices(access: _token);
      expect(devices, hasLength(2));
      expect(devices[1].isActive, isFalse);
    });

    test('deactivateDevice DELETEs the scoped device', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/notifications/devices/9/');
        expect(request.method, 'DELETE');
        return _json({
          'data': {'id': 9, 'is_active': false}
        });
      });
      final repo = NotificationsRepository(tokenStore: store, client: client);
      await repo.deactivateDevice(access: _token, id: 9);
    });
  });

  MockClient inboxClient() => MockClient((request) async {
        if (request.url.path == '/api/notifications/unread-count/') {
          return _json({
            'data': {'unread': 2}
          });
        }
        final readMatch =
            RegExp(r'^/api/notifications/(\d+)/read/$').firstMatch(
          request.url.path,
        );
        if (readMatch != null) {
          return _json({
            'data': _notificationJson(
                id: int.parse(readMatch.group(1)!),
                status: 'READ'),
          });
        }
        if (request.url.path == '/api/notifications/') {
          return _json({
            'data': {
              'results': [
                _notificationJson(
                    id: 1, type: 'EMERGENCY', priority: 'CRITICAL',
                    route: 'emergency'),
                _notificationJson(
                    id: 2, type: 'COMMUNITY', priority: 'NORMAL',
                    route: 'community'),
                _notificationJson(
                    id: 3,
                    type: 'BLOOD',
                    priority: 'HIGH',
                    status: 'READ'),
              ],
            }
          });
        }
        return http.Response('not found', 404);
      });

  testWidgets('inbox groups by category and shows unread + priority',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsHomeView(
          accessToken: _token,
          repository: NotificationsRepository(
            tokenStore: EphemeralTokenStore(),
            client: inboxClient(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unread · 2'), findsOneWidget);
    // Inbox is grouped by category; section headers are uppercased.
    expect(find.text('EMERGENCY ALERTS'), findsOneWidget);
    expect(find.text('COMMUNITY ACTIVITY'), findsOneWidget);
    expect(find.text('BLOOD NETWORK & DONORS'), findsOneWidget);
  });

  testWidgets('tapping a notification deep-links to an allowed route',
      (tester) async {
    final seen = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          CommunityPage.routeName: (_) {
            seen.add(CommunityPage.routeName);
            return const Scaffold(body: Text('community-target'));
          },
          MedicationPage.routeName: (_) {
            seen.add(MedicationPage.routeName);
            return const Scaffold(body: Text('medication-target'));
          },
        },
        home: NotificationsHomeView(
          accessToken: _token,
          repository: NotificationsRepository(
            tokenStore: EphemeralTokenStore(),
            client: inboxClient(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('T2'));
    await tester.pumpAndSettle();
    expect(seen, [CommunityPage.routeName]);
  });

  group('preferences surface', () {
    MockClient prefsClient() => MockClient((request) async {
          if (request.url.path == '/api/notifications/preferences/' &&
              request.method == 'GET') {
            return _json({
              'data': {
                'preferences': {'BLOOD': false}
              }
            });
          }
          return http.Response('not found', 404);
        });

    testWidgets('shows grouped switches with emergency locked on',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsHomeView(
            accessToken: _token,
            repository: NotificationsRepository(
              tokenStore: EphemeralTokenStore(),
              client: prefsClient(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.preferences));
      await tester.pumpAndSettle();

      expect(find.text('MEDICAL & SAFETY'), findsOneWidget);
      expect(find.text('Emergency alerts'), findsOneWidget);
      expect(find.text(AppStrings.emergencyLockedHelp), findsOneWidget);
      expect(find.text('Blood network & donors'), findsOneWidget);

      final emergencySwitch = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('Emergency alerts'),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(emergencySwitch.onChanged, isNull);
      expect(emergencySwitch.value, isTrue);
    });
  });
}