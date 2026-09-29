import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_config.dart';
import 'package:sicklers_warriors/features/admin/data/admin_repository.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/public/data/content_repository.dart';

const _token = 'test-access';

void main() {
  group('ContentRepository (public content)', () {
    test('listNews parses pagination, filters and resolves media URLs', () async {
      final repo = ContentRepository(
        client: MockClient((request) async {
          expect(request.url.path, '/api/content/news/');
          expect(request.url.queryParameters['page'], '2');
          expect(request.url.queryParameters['category'], 'BLOOD');
          expect(request.url.queryParameters['featured'], 'true');
          return http.Response(
            jsonEncode({
              'count': 1,
              'next': 'http://localhost:8000/api/content/news/?page=3',
              'previous': null,
              'results': [
                {
                  'uid': 'news-1',
                  'title': 'Quarterly Blood Drive',
                  'category': 'BLOOD',
                  'category_label': 'Blood',
                  'excerpt': 'Come give back.',
                  'body': '',
                  'cover_url': '/media/covers/drive.png',
                  'cover_alt': 'Drive',
                  'tags': ['blood'],
                  'featured': true,
                  'published_at': '2026-09-01T10:00:00Z',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final page = await repo.listNews(page: 2, category: 'BLOOD', featured: true);

      expect(page.items, hasLength(1));
      expect(page.hasNext, isTrue);
      expect(page.items.first.title, 'Quarterly Blood Drive');
      expect(page.items.first.categoryLabel, 'Blood');
      expect(page.items.first.featured, isTrue);
      expect(page.items.first.coverUrl, startsWith('http://localhost:8000/media/covers/'));
    });

    test('getNews parses detail body', () async {
      final repo = ContentRepository(
        client: MockClient((request) async {
          expect(request.url.path, '/api/content/news/news-1/');
          return http.Response(
            jsonEncode({
              'uid': 'news-1',
              'title': 'Drive',
              'category': 'BLOOD',
              'category_label': 'Blood',
              'excerpt': 'x',
              'body': '<p>Full story.</p>',
              'cover_url': '',
              'cover_alt': '',
              'tags': [],
              'featured': false,
              'published_at': '2026-09-01T10:00:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final detail = await repo.getNews('news-1');
      expect(detail.body, '<p>Full story.</p>');
      expect(detail.coverUrl, isEmpty);
    });

    test('listTicker accepts the bare-list payload from the backend', () async {
      final repo = ContentRepository(
        client: MockClient((request) async {
          expect(request.url.path, '/api/content/ticker/');
          return http.Response(
            jsonEncode([
              {'message': 'Emergency blood needed', 'announcement_type': 'URGENT', 'is_urgent': true},
              {'message': 'Support group tonight', 'announcement_type': 'EVENT', 'is_urgent': false},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final ticker = await repo.listTicker();
      expect(ticker, hasLength(2));
      expect(ticker.first.message, 'Emergency blood needed');
      expect(ticker.first.isUrgent, isTrue);
    });

    test('error payloads are carved into ContentException', () async {
      final repo = ContentRepository(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'error': {'code': 'NOT_FOUND', 'message': 'News not found.'},
              }),
              404,
            )),
      );

      expect(
        () => repo.getNews('nope'),
        throwsA(isA<ContentException>()
            .having((e) => e.code, 'code', 'NOT_FOUND')
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('AdminRepository (content CMS)', () {
    final store = EphemeralTokenStore();

    test('listNewsArticles passes status filter and parses rows', () async {
      final repo = AdminRepository(
        tokenStore: store,
        client: MockClient((request) async {
          expect(request.url.path, '/api/admin/content/news/');
          expect(request.url.queryParameters['status'], 'DRAFT');
          return http.Response(
            jsonEncode({
              'data': {
                'results': [
                  {
                    'uid': 'n-1',
                    'title': 'Draft post',
                    'category': 'COMMUNITY',
                    'category_label': 'Community',
                    'excerpt': 'draft',
                    'body': '',
                    'cover_url': '',
                    'cover_alt': '',
                    'tags': ['x'],
                    'featured': false,
                    'status': 'DRAFT',
                    'author': {'display_name': 'Admin'},
                    'published_at': null,
                    'created_at': '2026-09-27T10:00:00Z',
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final rows = await repo.listNewsArticles(access: _token, status: 'DRAFT');
      expect(rows, hasLength(1));
      expect(rows.first.status, 'DRAFT');
      expect(rows.first.categoryLabel, 'Community');
      expect(rows.first.authorName, 'Admin');
    });

    test('setNewsStatus hits the action endpoint', () async {
      final repo = AdminRepository(
        tokenStore: store,
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/admin/content/news/n-1/publish/');
          return http.Response(jsonEncode({'data': {'status': 'PUBLISHED'}}), 200);
        }),
      );

      await repo.setNewsStatus(access: _token, uid: 'n-1', action: 'publish');
    });

    test('uploadNewsCover is a real multipart request', () async {
      final repo = AdminRepository(
        tokenStore: store,
        client: MockClient((request) async {
          expect(request.url.path, '/api/admin/content/news/n-1/cover/');
          expect(request.method, 'POST');
          expect(request.headers['content-type'], contains('multipart/form-data'));
          expect(request.body, contains('image/png'));
          expect(request.body, contains('filename="cover.png"'));
          expect(request.body, contains('name="alt"'));
          expect(request.body, contains('Alt text'));
          return http.Response(jsonEncode({'data': {'ok': true}}), 200);
        }),
      );

      await repo.uploadNewsCover(
        access: _token,
        uid: 'n-1',
        bytes: [1, 2, 3, 4],
        filename: 'cover.png',
        contentType: 'image/png',
        alt: 'Alt text',
      );
    });

    test('ticker create + activate round-trip', () async {
      final repo = AdminRepository(
        tokenStore: store,
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/admin/content/ticker/') {
            return http.Response(
              jsonEncode({
                'data': {
                  'uid': 't-1',
                  'message': 'Hello',
                  'announcement_type': 'INFO',
                  'announcement_type_label': 'Info',
                  'link_url': '',
                  'is_active': false,
                  'priority': 0,
                  'start_at': null,
                  'end_at': null,
                },
              }),
              201,
            );
          }
          expect(request.url.path, '/api/admin/content/ticker/t-1/activate/');
          return http.Response(jsonEncode({'data': {'is_active': true}}), 200);
        }),
      );

      final created =
          await repo.createTicker(access: _token, message: 'Hello', type: 'INFO');
      expect(created.uid, 't-1');
      expect(created.typeLabel, 'Info');
      await repo.setTickerActive(access: _token, uid: 't-1', active: true);
    });
  });

  test('AppConfig API base is the loopback test target', () {
    expect(AppConfig.apiBaseUrl, contains('localhost'));
  });
}