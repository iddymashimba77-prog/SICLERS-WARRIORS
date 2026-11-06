import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/theme/app_theme.dart';
import 'package:sicklers_warriors/features/ai_assistant/data/ai_repository.dart';
import 'package:sicklers_warriors/features/ai_assistant/presentation/pages/ai_assistant_page.dart';
import 'package:sicklers_warriors/features/auth/data/auth_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sicklers_warriors/features/emergency/presentation/pages/emergency_page.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> _conversation(
  String uid,
  String title, {
  int messageCount = 2,
  List<Map<String, dynamic>> messages = const [],
  DateTime? lastActivity,
}) {
  final stamp = (lastActivity ?? DateTime.parse('2026-10-01T10:05:00Z'))
      .toUtc()
      .toIso8601String();
  return {
    'uid': uid,
    'title': title,
    'created_at': stamp,
    'updated_at': stamp,
    'last_activity_at': stamp,
    'archived': false,
    'message_count': messageCount,
    'messages': messages,
  };
}

Map<String, dynamic> _turn({String? conversationUid}) => {
      'assistant_id': 'req-1',
      'use_case': 'education',
      'personalized': false,
      'emergency_action': false,
      'emergency_categories': <String>[],
      'safety': {'blocked': false, 'reason': null},
      'metrics': null,
      'sources': <Map<String, dynamic>>[],
      'context_used': false,
      'limitation': null,
      'message': 'An answer about sickle cell.',
      'disclaimer': 'AI-generated health information is for education only.',
      if (conversationUid != null) 'conversation_uid': conversationUid,
    };

Future<AuthController> _authenticated() async {
  final store = EphemeralTokenStore();
  await store.writeAccess('access-1');
  await store.writeRefresh('refresh-1');
  final controller = AuthController(
    repository: AuthRepository(
      tokenStore: store,
      client: MockClient((request) async => _json({
            'data': {
              'email': 'warrior@example.com',
              'first_name': 'Amina',
              'last_name': 'Mwaka',
              'account_status': 'ACTIVE',
              'role_codes': ['PATIENT'],
            },
          })),
    ),
  );
  await controller.restoreSession();
  return controller;
}

Widget _page(
  AuthController auth,
  AiRepository repo, {
  ThemeData? theme,
}) =>
    MaterialApp(
      locale: const Locale('en'),
      theme: theme ?? AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizationsDelegate.supportedLocales,
      home: AiAssistantPage(authController: auth, repository: repo),
      routes: {EmergencyPage.routeName: (_) => const EmergencyPage()},
    );

Future<void> _viewport(
  WidgetTester tester, {
  Size size = const Size(1000, 1500),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Persisted last-opened threads are per account; isolate every widget test
    // so one case cannot auto-restore a conversation created by another.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('history sidebar lists stored conversations', (tester) async {
    final repo = AiRepository(
      client: MockClient((request) async {
        if (request.url.path == '/api/ai-assistant/conversations/') {
          return _json([
            _conversation('c1', 'Conversation one'),
            _conversation('c2', 'Conversation two'),
          ]);
        }
        return _json({'data': _turn()});
      }),
    );

    await _viewport(tester);
    await tester.pumpWidget(_page(await _authenticated(), repo));
    await tester.pumpAndSettle();

    expect(find.text('Conversation one'), findsOneWidget);
    expect(find.text('Conversation two'), findsOneWidget);
  });

  testWidgets('tapping a conversation loads its messages', (tester) async {
    final repo = AiRepository(
      client: MockClient((request) async {
        if (request.url.path == '/api/ai-assistant/conversations/') {
          return _json([_conversation('c1', 'Conversation one')]);
        }
        if (request.url.path == '/api/ai-assistant/conversations/c1/') {
          return _json(_conversation('c1', 'Conversation one', messages: [
            {
              'uid': 'm1',
              'role': 'user',
              'content': 'earlier question',
              'created_at': '2026-10-01T10:00:00Z',
            },
            {
              'uid': 'm2',
              'role': 'assistant',
              'content': 'earlier answer',
              'created_at': '2026-10-01T10:01:00Z',
            },
          ]));
        }
        return _json({'data': _turn()});
      }),
    );

    await _viewport(tester);
    await tester.pumpWidget(_page(await _authenticated(), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conversation one'));
    await tester.pumpAndSettle();

    expect(find.text('earlier question'), findsOneWidget);
    expect(find.text('earlier answer'), findsOneWidget);
  });

  testWidgets('reopening a stored emergency turn restores the SOS callout',
      (tester) async {
    final repo = AiRepository(
      client: MockClient((request) async {
        if (request.url.path == '/api/ai-assistant/conversations/') {
          return _json([_conversation('c1', 'Emergency history')]);
        }
        if (request.url.path == '/api/ai-assistant/conversations/c1/') {
          return _json(_conversation('c1', 'Emergency history', messages: [
            {
              'uid': 'm1',
              'role': 'user',
              'content': 'Severe chest pain',
              'created_at': '2026-10-01T10:00:00Z',
            },
            {
              'uid': 'm2',
              'role': 'assistant',
              'content': 'This may be an emergency. Seek urgent care.',
              'created_at': '2026-10-01T10:01:00Z',
              'meta': {
                'emergency_action': true,
                'emergency_categories': ['chest_pain'],
                'safety': {'blocked': true, 'reason': 'emergency'},
                'sources': <Map<String, dynamic>>[],
              },
            },
          ]));
        }
        return _json({'data': _turn()});
      }),
    );

    await _viewport(tester);
    await tester.pumpWidget(_page(await _authenticated(), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Emergency history'));
    await tester.pumpAndSettle();

    expect(find.text('This may be an emergency'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open emergency help'),
        findsOneWidget);
  });

  testWidgets('new chat clears the thread', (tester) async {
    final repo = AiRepository(
      client: MockClient((request) async {
        if (request.url.path == '/api/ai-assistant/conversations/') {
          return _json([_conversation('c1', 'Conversation one')]);
        }
        if (request.url.path == '/api/ai-assistant/conversations/c1/') {
          return _json(_conversation('c1', 'Conversation one', messages: [
            {'uid': 'm1', 'role': 'user', 'content': 'old message'},
          ]));
        }
        return _json({'data': _turn()});
      }),
    );

    await _viewport(tester);
    await tester.pumpWidget(_page(await _authenticated(), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conversation one'));
    await tester.pumpAndSettle();
    expect(find.text('old message'), findsOneWidget);

    await tester.tap(find.byTooltip('New chat').first);
    await tester.pumpAndSettle();
    expect(find.text('old message'), findsNothing);
  });

  testWidgets('deleting a conversation calls the API and removes it',
      (tester) async {
    var deleted = false;
    final repo = AiRepository(
      client: MockClient((request) async {
        if (request.method == 'DELETE' &&
            request.url.path == '/api/ai-assistant/conversations/c2/') {
          deleted = true;
          return http.Response('', 204);
        }
        if (request.url.path == '/api/ai-assistant/conversations/') {
          return _json([
            _conversation('c1', 'Conversation one'),
            _conversation('c2', 'Conversation two'),
          ]);
        }
        return _json({'data': _turn()});
      }),
    );

    await _viewport(tester);
    await tester.pumpWidget(_page(await _authenticated(), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Conversation options').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('Conversation two'), findsNothing);
  });

  testWidgets('sending creates a conversation and refreshes the sidebar',
      (tester) async {
    var listCalls = 0;
    List<Map<String, dynamic>> conversations = [];
    final repo = AiRepository(
      client: MockClient((request) async {
        if (request.url.path == '/api/ai-assistant/conversations/') {
          listCalls++;
          return _json(conversations);
        }
        if (request.url.path == '/api/ai/chat/') {
          conversations = [_conversation('new-1', 'What is sickle cell?')];
          return _json({'data': _turn(conversationUid: 'new-1')});
        }
        return _json({'data': _turn()});
      }),
    );

    await _viewport(tester);
    await tester.pumpWidget(_page(await _authenticated(), repo));
    await tester.pumpAndSettle();
    expect(listCalls, 1);

    await tester.enterText(find.byKey(const ValueKey('ai-composer-input')), 'What is sickle cell?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(listCalls, greaterThan(1));
    expect(find.text('What is sickle cell?'), findsWidgets);
  });

  testWidgets('history groups conversations by recency', (tester) async {
    final now = DateTime.now();
    final repo = AiRepository(
      client: MockClient((request) async {
        if (request.url.path == '/api/ai-assistant/conversations/') {
          return _json([
            _conversation('c1', 'Today chat', lastActivity: now),
            _conversation('c2', 'Yesterday chat',
                lastActivity: now.subtract(const Duration(days: 1))),
            _conversation('c3', 'Week chat',
                lastActivity: now.subtract(const Duration(days: 3))),
            _conversation('c4', 'Month chat',
                lastActivity: now.subtract(const Duration(days: 15))),
            _conversation('c5', 'Old chat',
                lastActivity: now.subtract(const Duration(days: 60))),
          ]);
        }
        return _json({'data': _turn()});
      }),
    );

    await _viewport(tester);
    await tester.pumpWidget(_page(await _authenticated(), repo));
    await tester.pumpAndSettle();

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('PREVIOUS 7 DAYS'), findsOneWidget);
    expect(find.text('PREVIOUS 30 DAYS'), findsOneWidget);
    expect(find.text('OLDER'), findsOneWidget);
  });

  testWidgets('search queries the server and clear restores the history',
      (tester) async {
    final searches = <String?>[];
    final all = [
      _conversation('c1', 'Pain crisis plan'),
      _conversation('c2', 'Clinic visit'),
    ];
    final repo = AiRepository(
      client: MockClient((request) async {
        if (request.url.path == '/api/ai-assistant/conversations/') {
          final search = request.url.queryParameters['search'];
          searches.add(search);
          if (search == 'pain') return _json([all.first]);
          return _json(all);
        }
        return _json({'data': _turn()});
      }),
    );

    await _viewport(tester);
    await tester.pumpWidget(_page(await _authenticated(), repo));
    await tester.pumpAndSettle();
    expect(find.text('Clinic visit'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('ai-search-input')),
      'pain',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(searches.contains('pain'), isTrue);
    expect(find.text('Pain crisis plan'), findsOneWidget);
    expect(find.text('Clinic visit'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Clinic visit'), findsOneWidget);
  });

  testWidgets('rename updates the API and the sidebar immediately',
      (tester) async {
    String? receivedTitle;
    final repo = AiRepository(
      client: MockClient((request) async {
        if (request.method == 'PATCH' &&
            request.url.path == '/api/ai-assistant/conversations/c1/') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          receivedTitle = body['title'] as String?;
          return _json(_conversation('c1', receivedTitle!));
        }
        if (request.url.path == '/api/ai-assistant/conversations/') {
          return _json([_conversation('c1', 'Conversation one')]);
        }
        return _json({'data': _turn()});
      }),
    );

    await _viewport(tester);
    await tester.pumpWidget(_page(await _authenticated(), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Conversation options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Renamed chat',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(receivedTitle, 'Renamed chat');
    expect(find.text('Renamed chat'), findsOneWidget);
    expect(find.text('Conversation one'), findsNothing);
  });

  testWidgets('mobile history is a slide-out panel that closes on selection',
      (tester) async {
    final repo = AiRepository(
      client: MockClient((request) async {
        if (request.url.path == '/api/ai-assistant/conversations/') {
          return _json([_conversation('c1', 'Conversation one')]);
        }
        if (request.url.path == '/api/ai-assistant/conversations/c1/') {
          return _json(_conversation('c1', 'Conversation one', messages: [
            {'uid': 'm1', 'role': 'user', 'content': 'earlier question'},
          ]));
        }
        return _json({'data': _turn()});
      }),
    );

    await _viewport(tester, size: const Size(400, 900));
    await tester.pumpWidget(_page(await _authenticated(), repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ai-search-input')), findsNothing);
    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    expect(find.text('Conversation one'), findsOneWidget);

    await tester.tap(find.text('Conversation one'));
    await tester.pumpAndSettle();

    expect(find.text('earlier question'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-search-input')), findsNothing);
  });

  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    testWidgets('history renders in ${entry.key} theme', (tester) async {
      final repo = AiRepository(
        client: MockClient((request) async {
          if (request.url.path == '/api/ai-assistant/conversations/') {
            return _json([_conversation('c1', 'Conversation one')]);
          }
          return _json({'data': _turn()});
        }),
      );

      await _viewport(tester);
      await tester.pumpWidget(
        _page(await _authenticated(), repo, theme: entry.value),
      );
      await tester.pumpAndSettle();

      expect(find.text('Conversation one'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
