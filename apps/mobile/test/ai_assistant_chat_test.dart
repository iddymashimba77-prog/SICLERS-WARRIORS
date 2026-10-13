import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/features/ai_assistant/data/ai_repository.dart';
import 'package:sicklers_warriors/features/ai_assistant/presentation/pages/ai_assistant_page.dart';
import 'package:sicklers_warriors/features/auth/data/auth_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sicklers_warriors/features/emergency/presentation/pages/emergency_page.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// Exactly the `_finish()` shape `AiAssistantService` returns.
Map<String, dynamic> _turn({
  String message = 'Rest, hydration and prompt pain relief help most crises.',
  bool emergency = false,
  bool blocked = false,
  bool withSources = false,
}) =>
    {
      'assistant_id': 'req-1',
      'use_case': 'education',
      'personalized': false,
      'emergency_action': emergency,
      'emergency_categories': emergency ? ['chest_pain'] : <String>[],
      'safety': {'blocked': blocked, 'reason': blocked ? 'medical_advice' : null},
      'metrics': null,
      'sources': withSources
          ? [
              {
                'uid': 'e1',
                'title': 'Managing pain at home',
                'snippet': 'Hydration, rest and early pain relief.',
                'score': 6,
              },
            ]
          : <Map<String, dynamic>>[],
      'context_used': false,
      'limitation': null,
      'message': message,
      'disclaimer': 'AI-generated health information is for education only.',
    };

Future<AuthController> _authenticated() async {
  final store = EphemeralTokenStore();
  await store.writeAccess('access-1');
  await store.writeRefresh('refresh-1');
  final controller = AuthController(
    repository: AuthRepository(
      tokenStore: store,
      client: MockClient((request) async {
        expect(request.url.path, '/api/auth/me/');
        return _json({
          'data': {
            'email': 'warrior@example.com',
            'first_name': 'Amina',
            'last_name': 'Mwaka',
            'account_status': 'ACTIVE',
            'role_codes': ['PATIENT'],
          },
        });
      }),
    ),
  );
  await controller.restoreSession();
  return controller;
}

/// English locale so assertions match the EN copy (the standalone fallback
/// otherwise resolves to the Kiswahili-first brand default).
Widget _page({required AuthController auth, required AiRepository repo}) =>
    MaterialApp(
      locale: const Locale('en'),
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

/// Tall viewport so the welcome panel and composer are both on screen.
Future<void> _viewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1500);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AI assistant chat (FR-AI-001/002/006)', () {
    testWidgets('a signed-out visitor gets the shared signed-out prompt',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AiAssistantPage()));
      await tester.pump();
      expect(find.text(AppStrings.notSignedIn), findsOneWidget);
    });

    testWidgets('one turn posts to /api/ai/chat/ and renders the answer',
        (tester) async {
      Map<String, dynamic>? sent;
      final repo = AiRepository(
        client: MockClient((request) async {
          expect(request.url.path, '/api/ai/chat/');
          expect(request.headers['Authorization'], 'Bearer access-1');
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'data': _turn(withSources: true)});
        }),
      );

      await _viewport(tester);
      await tester.pumpWidget(_page(auth: await _authenticated(), repo: repo));
      await tester.pump();

      // Welcome suggestions are real sends, not decoration.
      await tester.tap(find.text('What can trigger a pain crisis?'));
      await tester.pumpAndSettle();

      expect(sent, isNotNull);
      expect(sent!['message'], 'What can trigger a pain crisis?');
      expect(sent!['use_case'], 'education');
      expect(sent!['personalized'], isTrue);
      expect(
        find.text('Rest, hydration and prompt pain relief help most crises.'),
        findsOneWidget,
      );
      expect(find.text('Managing pain at home'), findsOneWidget,
          reason: 'approved-knowledge citations are listed');
      expect(find.textContaining('not a medical diagnosis'), findsOneWidget,
          reason: 'the non-diagnosis disclaimer stays pinned');
    });

    testWidgets('an emergency turn surfaces the SOS pathway, not just text',
        (tester) async {
      final repo = AiRepository(
        client: MockClient(
          (_) async => _json({'data': _turn(emergency: true)}),
        ),
      );

      await _viewport(tester);
      await tester.pumpWidget(_page(auth: await _authenticated(), repo: repo));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Severe chest pain now');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(find.text('This may be an emergency'), findsOneWidget);
      final open = find.widgetWithText(FilledButton, 'Open emergency help');
      expect(open, findsOneWidget);

      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(EmergencyPage), findsOneWidget);
    });

    testWidgets('a refused turn shows the refusal and no emergency banner',
        (tester) async {
      final repo = AiRepository(
        client: MockClient(
          (_) async => _json({
            'data': _turn(
              message: 'I cannot help with that request.',
              blocked: true,
            ),
          }),
        ),
      );

      await _viewport(tester);
      await tester.pumpWidget(_page(auth: await _authenticated(), repo: repo));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Write me a prescription');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(find.text('I cannot help with that request.'), findsOneWidget);
      expect(find.text('I can’t help with that request'), findsOneWidget);
      expect(find.text('This may be an emergency'), findsNothing);
      expect(find.text('Open emergency help'), findsNothing);
    });

    testWidgets('the 6/min throttle surfaces the ask-limit message',
        (tester) async {
      final repo = AiRepository(
        client: MockClient(
          (_) async => _json({
            'error': {'code': 'throttled', 'message': 'Request was throttled.'},
          }, 429),
        ),
      );

      await _viewport(tester);
      await tester.pumpWidget(_page(auth: await _authenticated(), repo: repo));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Anything at all');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'You have reached the ask limit for now. Try again in a minute.'),
        findsOneWidget,
      );
    });
  });
}
