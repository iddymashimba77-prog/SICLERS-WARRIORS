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
import 'package:sicklers_warriors/features/auth/presentation/widgets/session_scope.dart';
import 'package:sicklers_warriors/features/public/data/content_repository.dart';
import 'package:sicklers_warriors/features/public/presentation/pages/news_list_page.dart';
import 'package:sicklers_warriors/shared/widgets/signed_out_gate.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

class _NewsHarness {
  int contentRequests = 0;

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
    if (path.endsWith('/content/news/categories/')) {
      return _json({
        'data': [
          {'code': 'HEALTH', 'label': 'Health'},
        ],
      });
    }
    if (path.endsWith('/content/news/')) {
      contentRequests += 1;
      return _json({
        'data': {
          'count': 1,
          'next': null,
          'previous': null,
          'results': [
            {
              'uid': 'a' * 32,
              'title': 'Community update',
              'category': 'HEALTH',
              'category_label': 'Health',
              'excerpt': 'A member story.',
              'featured': false,
              'published_at': '2026-11-01T10:00:00Z',
              'author': {'display_name': 'Member'},
            },
          ],
        },
      });
    }
    return _json({'data': <String, dynamic>{}}, 404);
  });

  ContentRepository get repository => ContentRepository(client: client);

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

Widget _app(Widget home, {AuthController? auth}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizationsDelegate.supportedLocales,
    home: auth == null
        ? home
        : SessionScope(controller: auth, child: home),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signed-out visitors see the gate without a content request',
      (tester) async {
    final harness = _NewsHarness();
    await tester.pumpWidget(_app(NewsListPage(repository: harness.repository)));
    await tester.pump();

    expect(find.byType(SignedOutGate), findsOneWidget);
    expect(find.text(AppStrings.notSignedIn), findsOneWidget);
    expect(find.text('Latest News & Updates'), findsNothing);
    expect(harness.contentRequests, 0);
  });

  testWidgets('signed-in members reach the news archive', (tester) async {
    final harness = _NewsHarness();
    final auth = await harness.auth();
    await tester.pumpWidget(
      _app(NewsListPage(repository: harness.repository), auth: auth),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Latest News & Updates'), findsOneWidget);
    expect(find.text('Community update'), findsOneWidget);
    expect(harness.contentRequests, 1);
  });
}
