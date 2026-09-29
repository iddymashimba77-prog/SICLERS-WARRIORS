import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/education/data/education_repository.dart';
import 'package:sicklers_warriors/features/education/presentation/pages/education_bookmarks_page.dart';
import 'package:sicklers_warriors/features/education/presentation/pages/education_detail_page.dart';
import 'package:sicklers_warriors/features/education/presentation/pages/education_page.dart';

const _token = 'test-access';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> _categoryJson(
        {int id = 1, String code = 'NUTRITION', String name = 'Nutrition'}) =>
    {'id': id, 'code': code, 'name': name};

Map<String, dynamic> _contentJson({
  String uid = 'e-1',
  String title = 'Eating well with sickle cell',
  String body = 'Hydration and iron awareness help day to day.',
  String categoryCode = 'NUTRITION',
  String categoryName = 'Nutrition',
  String status = 'PUBLISHED',
}) =>
    {
      'id': 1,
      'uid': uid,
      'author': {'uid': 'doc-1', 'display_name': 'Dr. Mensah'},
      'title': title,
      'body': body,
      'category': _categoryJson(code: categoryCode, name: categoryName),
      'status': status,
      'cover_url': '',
      'published_at': '2026-09-20T10:00:00Z',
      'created_at': '2026-09-19T10:00:00Z',
      'is_author': false,
    };

void main() {
  final store = EphemeralTokenStore();

  group('EducationRepository (Stage 4.11)', () {
    test('listCategories + listContent hit approved paths with filters',
        () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        expect(request.headers['Authorization'], 'Bearer $_token');
        if (request.url.path == '/api/education/categories/') {
          return _json({
            'data': {
              'results': [_categoryJson(), _categoryJson(id: 2, code: 'EXERCISE', name: 'Exercise')]
            }
          });
        }
        expect(request.url.queryParameters['q'], 'diet');
        expect(request.url.queryParameters['category'], 'NUTRITION');
        return _json({
          'data': {
            'results': [_contentJson()]
          }
        });
      });
      final repo = EducationRepository(tokenStore: store, client: client);
      final categories = await repo.listCategories(access: _token);
      expect(categories, hasLength(2));
      expect(categories.first.name, 'Nutrition');
      final content = await repo.listContent(
        access: _token,
        query: 'diet',
        category: 'NUTRITION',
      );
      expect(content.single.author.displayName, 'Dr. Mensah');
      expect(content.single.category.code, 'NUTRITION');
      expect(calls, [
        'GET /api/education/categories/',
        'GET /api/education/content/',
      ]);
    });

    test('listContent submits page params for pagination', () async {
      final seen = <Map<String, String?>>[];
      final client = MockClient((request) async {
        seen.add(request.url.queryParameters);
        return _json({
          'data': {
            'results': [_contentJson(uid: 'e-p', title: 'Page two')]
          }
        });
      });
      final repo = EducationRepository(tokenStore: store, client: client);
      final items = await repo.listContent(
        access: _token,
        query: 'diet',
        page: 2,
        pageSize: 50,
      );
      expect(seen.single['page'], '2');
      expect(seen.single['page_size'], '50');
      expect(seen.single['q'], 'diet');
      expect(items.single.uid, 'e-p');
    });

    test('getContent parses the nested category + author projection', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/education/content/e-1/');
        return _json({
          'data': _contentJson(
            body: 'Read the <b>full</b> article',
            categoryCode: 'CRISIS_PREVENTION',
            categoryName: 'Crisis Prevention',
          )
        });
      });
      final repo = EducationRepository(tokenStore: store, client: client);
      final item = await repo.getContent(access: _token, uid: 'e-1');
      expect(item.uid, 'e-1');
      expect(item.category.name, 'Crisis Prevention');
      expect(item.isPublished, isTrue);
    });

    test('bookmarks are local and session-only', () {
      final repo = EducationRepository(tokenStore: store);
      expect(repo.isBookmarked('e-1'), isFalse);
      expect(repo.toggleBookmark('e-1'), isTrue);
      expect(repo.isBookmarked('e-1'), isTrue);
      expect(repo.toggleBookmark('e-1'), isFalse);
      expect(repo.hasBookmarks, isFalse);
    });
  });

  group('Education widgets (Stage 4.11)', () {
    testWidgets('library renders category chips + article cards',
        (tester) async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/education/categories/') {
          return _json({
            'data': {
              'results': [_categoryJson()]
            }
          });
        }
        return _json({
          'data': {
            'results': [_contentJson()]
          }
        });
      });
      final repo = EducationRepository(tokenStore: store, client: client);
      await tester.pumpWidget(MaterialApp(
        home: EducationLibraryView(accessToken: _token, repository: repo),
      ));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.allCategories), findsOneWidget);
      expect(find.text('Nutrition'), findsWidgets);
      expect(find.text('Eating well with sickle cell'), findsOneWidget);
    });

    testWidgets('search re-loads the library with the query', (tester) async {
      var queried = false;
      final client = MockClient((request) async {
        if (request.url.path == '/api/education/categories/') {
          return _json({'data': {'results': [_categoryJson()]}});
        }
        if (request.url.queryParameters['q'] == 'hydration') queried = true;
        return _json({
          'data': {
            'results': queried ? [_contentJson(uid: 'e-2', title: 'Hydration tips')] : []
          }
        });
      });
      final repo = EducationRepository(tokenStore: store, client: client);
      await tester.pumpWidget(MaterialApp(
        home: EducationLibraryView(accessToken: _token, repository: repo),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'hydration');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(queried, isTrue);
      expect(find.text('Hydration tips'), findsOneWidget);
    });

    testWidgets('detail shows the medical disclaimer and can be bookmarked',
        (tester) async {
      final client = MockClient((request) async {
        return _json({
          'data': _contentJson(body: 'Stay hydrated by drinking water regularly.')
        });
      });
      final repo = EducationRepository(tokenStore: store, client: client);
      await tester.pumpWidget(MaterialApp(
        home: EducationDetailView(
          accessToken: _token,
          repository: repo,
          contentUid: 'e-1',
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(AppStrings.educationNotMedicalAdvice),
        findsOneWidget,
      );
      expect(find.text('Eating well with sickle cell'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pumpAndSettle();
      expect(repo.isBookmarked('e-1'), isTrue);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
    });

    testWidgets('bookmarks page shows an empty state when nothing is saved',
        (tester) async {
      final client = MockClient((request) async {
        return http.Response('not found', 404);
      });
      final repo = EducationRepository(tokenStore: store, client: client);
      expect(repo.hasBookmarks, isFalse);
      await tester.pumpWidget(MaterialApp(
        home: EducationBookmarksView(accessToken: _token, repository: repo),
      ));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(AppStrings.noBookmarksHint),
        findsOneWidget,
      );
    });

    testWidgets('bookmarks page fetches saved articles', (tester) async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/education/content/e-9/');
        return _json({
          'data': _contentJson(uid: 'e-9', title: 'Safe exercise routines')
        });
      });
      final repo = EducationRepository(tokenStore: store, client: client);
      repo.toggleBookmark('e-9');
      await tester.pumpWidget(MaterialApp(
        home: EducationBookmarksView(accessToken: _token, repository: repo),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Safe exercise routines'), findsOneWidget);
      expect(repo.isBookmarked('e-9'), isTrue);
    });

    testWidgets('bookmarks fetch in parallel and skip a 404 article',
        (tester) async {
      final inFlight = <String>{};
      var maxInFlight = 0;
      final client = MockClient((request) async {
        inFlight.add(request.url.path);
        maxInFlight = maxInFlight > inFlight.length
            ? maxInFlight
            : inFlight.length;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        inFlight.remove(request.url.path);
        if (request.url.path == '/api/education/content/e-gone/') {
          return http.Response('not found', 404);
        }
        return _json({
          'data': _contentJson(uid: 'e-9', title: 'Safe exercise routines')
        });
      });
      final repo = EducationRepository(tokenStore: store, client: client);
      repo.toggleBookmark('e-9');
      repo.toggleBookmark('e-gone');
      await tester.pumpWidget(MaterialApp(
        home: EducationBookmarksView(accessToken: _token, repository: repo),
      ));
      await tester.pumpAndSettle();
      expect(maxInFlight, greaterThanOrEqualTo(2),
          reason: 'bookmarked articles must be fetched concurrently');
      expect(find.text('Safe exercise routines'), findsOneWidget);
      // The deleted article is quietly dropped instead of failing the list.
      expect(find.text('not found'), findsNothing);
    });
  });
}