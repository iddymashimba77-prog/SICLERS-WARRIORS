import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/features/auth/data/auth_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sicklers_warriors/features/hydration/data/hydration_repository.dart';
import 'package:sicklers_warriors/features/hydration/presentation/pages/hydration_page.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> _day({
  int? goal,
  List<Map<String, dynamic>> entries = const [],
}) {
  final consumed = entries.fold<int>(
    0,
    (sum, entry) => sum + (entry['amount_ml'] as num).toInt(),
  );
  return {
    'date': '2026-11-07',
    'goal_ml': goal,
    'consumed_ml': consumed,
    'remaining_ml': goal == null ? null : (goal - consumed).clamp(0, goal),
    'progress_pct': goal == null || goal == 0
        ? null
        : ((consumed / goal) * 100).round().clamp(0, 100),
    'entries': entries,
  };
}

class _HydrationHarness {
  _HydrationHarness();

  int? goal;
  final List<Map<String, dynamic>> entries = [];
  int nextId = 0;
  String? lastPostBody;
  String? lastPatchBody;

  late final MockClient client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/auth/me/')) {
      return _json({
        'data': {
          'email': 'warrior@example.com',
          'account_status': 'ACTIVE',
          'role_codes': ['PATIENT'],
        },
      });
    }
    if (path.endsWith('/patients/me/hydration/goal/')) {
      lastPatchBody = request.body;
      goal = (jsonDecode(request.body)['hydration_goal_ml'] as num?)?.toInt();
      return _json({
        'data': {'hydration_goal_ml': goal},
      });
    }
    if (path.endsWith('/patients/me/hydration/')) {
      if (request.method == 'POST') {
        lastPostBody = request.body;
        final amount = (jsonDecode(request.body)['amount_ml'] as num).toInt();
        final entry = {
          'uid': 'entry-${nextId++}',
          'amount_ml': amount,
          'recorded_at': '2026-11-07T10:15:00Z',
        };
        entries.add(entry);
        return _json({'data': entry}, 201);
      }
      return _json({
        'data': _day(goal: goal, entries: entries),
      });
    }
    return _json({'data': <String, dynamic>{}}, 404);
  });

  HydrationRepository get repository => HydrationRepository(client: client);

  Future<AuthController> auth() async {
    final store = EphemeralTokenStore();
    await store.writeAccess('access-1');
    await store.writeRefresh('refresh-1');
    final controller = AuthController(
      repository: AuthRepository(tokenStore: store, client: client),
    );
    await controller.restoreSession();
    return controller;
  }
}

Widget _app(AuthController auth, HydrationRepository repository) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizationsDelegate.supportedLocales,
    home: HydrationPage(authController: auth, repository: repository),
  );
}

Future<void> _tallViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts without inventing a fluid goal', (tester) async {
    await _tallViewport(tester);
    final harness = _HydrationHarness();
    await tester.pumpWidget(_app(await harness.auth(), harness.repository));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('No goal set'), findsOneWidget);
    expect(find.text('Set goal'), findsOneWidget);
    expect(find.text('No intake logged yet'), findsOneWidget);
    expect(find.textContaining('does not replace medical advice'), findsOneWidget);
    expect(harness.goal, isNull);
  });

  testWidgets('quick add posts intake and refreshes the day', (tester) async {
    await _tallViewport(tester);
    final harness = _HydrationHarness();
    await tester.pumpWidget(_app(await harness.auth(), harness.repository));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const ValueKey('hydration-add-500')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.lastPostBody, contains('"amount_ml":500'));
    expect(find.byKey(const ValueKey('hydration-entry-entry-0')), findsOneWidget);
    expect(find.text('500 ml'), findsWidgets);
  });

  testWidgets('sets a personal goal and shows progress', (tester) async {
    await _tallViewport(tester);
    final harness = _HydrationHarness();
    harness.entries.add({
      'uid': 'entry-seed',
      'amount_ml': 500,
      'recorded_at': '2026-11-07T09:00:00Z',
    });
    await tester.pumpWidget(_app(await harness.auth(), harness.repository));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const ValueKey('hydration-set-goal')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('hydration-goal-input')),
      '2000',
    );
    await tester.tap(find.byKey(const ValueKey('hydration-goal-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.lastPatchBody, contains('"hydration_goal_ml":2000'));
    expect(find.text('500 / 2000 ml'), findsOneWidget);
    expect(find.text('1500 ml remaining'), findsOneWidget);
  });

  testWidgets('rejects a goal outside the safe range before sending it',
      (tester) async {
    final harness = _HydrationHarness();
    await tester.pumpWidget(_app(await harness.auth(), harness.repository));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const ValueKey('hydration-set-goal')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('hydration-goal-input')),
      '100',
    );
    await tester.tap(find.byKey(const ValueKey('hydration-goal-save')));
    await tester.pump();

    expect(find.text('Enter a goal between 250 and 6000 ml.'), findsOneWidget);
    expect(harness.lastPatchBody, isNull);
  });

  testWidgets('signed-out visitors get the member gate', (tester) async {
    final harness = _HydrationHarness();
    final controller = AuthController(
      repository: AuthRepository(
        tokenStore: EphemeralTokenStore(),
        client: harness.client,
      ),
    );
    await tester.pumpWidget(_app(controller, harness.repository));
    await tester.pump();

    expect(find.text('Hydration'), findsOneWidget);
    expect(find.text(AppStrings.notSignedIn), findsOneWidget);
    expect(find.text(AppStrings.login), findsOneWidget);
  });
}
