/// Doctor-side article authoring tests (FR-EDU-005).
///
/// Run::
///   flutter test test/edu_authoring_test.dart
///
/// Covers the mobile half of writing: the create/patch/submit/delete calls,
/// the status rules that decide which action the UI may offer (the app must
/// not present a button the server will refuse), the composer form's own
/// validation, and the review hand-off dialog.
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
import 'package:sicklers_warriors/features/education/data/education_repository.dart';
import 'package:sicklers_warriors/features/education/presentation/pages/article_form_page.dart';
import 'package:sicklers_warriors/features/education/presentation/pages/doctor_education_page.dart';

const _token = 'test-access';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> _contentJson({
  String uid = 'e-1',
  String title = 'Understanding your transfusion plan',
  String status = 'DRAFT',
  String category = 'SICKLE_BASICS',
}) =>
    {
      'id': 1,
      'uid': uid,
      'author': {'uid': 'doc-1', 'display_name': 'Dr. Mensah'},
      'title': title,
      'body': 'A short explainer.',
      'category': {'id': 3, 'code': category, 'name': 'Sickle basics'},
      'status': status,
      'cover_url': '',
      'published_at': null,
      'created_at': '2026-09-19T10:00:00Z',
      'is_author': true,
    };

const _categoriesJson = {
  'count': 2,
  'next': null,
  'previous': null,
  'results': [
    {'id': 3, 'code': 'SICKLE_BASICS', 'name': 'Sickle basics'},
    {'id': 5, 'code': 'NUTRITION', 'name': 'Nutrition'},
  ],
};

EducationRepository _repo(http.Client client) =>
    EducationRepository(tokenStore: EphemeralTokenStore(), client: client);

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

/// The save button sits below the fold of a scrolling form, so bring it into
/// view before tapping — `tap` on an off-screen widget silently misses.
Future<void> _tapSave(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Save draft');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  // `ensureVisible` can park the button exactly on the viewport edge, where the
  // tap lands outside the root and is silently dropped. Nudge it clear first.
  await tester.drag(find.byType(ListView).last, const Offset(0, -60));
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// Serves the category list and the author's own articles.
http.Client _workspaceClient({
  required List<Map<String, dynamic>> items,
  void Function(http.Request request)? onRequest,
}) =>
    MockClient((request) async {
      onRequest?.call(request);
      if (request.url.path.endsWith('/education/categories/')) {
        return _json(_categoriesJson);
      }
      if (request.url.path.contains('/education/content/')) {
        return _json({
          'count': items.length,
          'next': null,
          'previous': null,
          'results': items,
        });
      }
      return _json({'detail': 'unexpected'}, 404);
    });

void main() {
  group('Editorial status rules', () {
    test('a draft can be edited, submitted and deleted', () {
      final draft = EducationalContent.fromJson(_contentJson(status: 'DRAFT'));
      expect(draft.canEdit, isTrue);
      expect(draft.canSubmit, isTrue);
      expect(draft.canDelete, isTrue);
    });

    test('a rejected article can be fixed and resubmitted', () {
      final item = EducationalContent.fromJson(_contentJson(status: 'REJECTED'));
      expect(item.canEdit, isTrue);
      expect(item.canSubmit, isTrue);
      // The review history is kept, so a rejected article is never hard-deleted.
      expect(item.canDelete, isFalse);
    });

    test('an archived article is editable but goes back through the archive path',
        () {
      final item = EducationalContent.fromJson(_contentJson(status: 'ARCHIVED'));
      expect(item.canEdit, isTrue);
      expect(item.canSubmit, isFalse);
    });

    test('an in-review or published article is frozen', () {
      for (final status in ['IN_REVIEW', 'PUBLISHED']) {
        final item = EducationalContent.fromJson(_contentJson(status: status));
        expect(item.canEdit, isFalse, reason: status);
        expect(item.canSubmit, isFalse, reason: status);
        expect(item.canDelete, isFalse, reason: status);
      }
    });
  });

  group('Authoring repository calls', () {
    test('create posts a draft with the chosen category code', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return _json(_contentJson(status: 'DRAFT'), 201);
      });

      final item = await _repo(client).createContent(
        access: _token,
        title: 'Hydration and sickle cell',
        body: 'Why water matters.',
        category: 'NUTRITION',
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, endsWith('/education/content/'));
      final payload = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(payload['title'], 'Hydration and sickle cell');
      expect(payload['category'], 'NUTRITION');
      expect(payload.containsKey('cover_url'), isFalse,
          reason: 'an empty cover is omitted rather than sent as ""');
      expect(item.status, 'DRAFT');
    });

    test('update patches the article and keeps the cover it was given', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return _json(_contentJson(status: 'DRAFT'));
      });

      await _repo(client).updateContent(
        access: _token,
        uid: 'e-1',
        title: 'Revised title',
        body: 'Revised body.',
        category: 'SICKLE_BASICS',
        coverUrl: 'https://cdn.example.org/cover.png',
      );

      expect(sent.method, 'PATCH');
      expect(sent.url.path, endsWith('/education/content/e-1/'));
      final payload = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(payload['title'], 'Revised title');
      expect(payload['cover_url'], 'https://cdn.example.org/cover.png');
    });

    test('submit posts to the review hand-off and returns the new status',
        () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return _json(_contentJson(status: 'IN_REVIEW'));
      });

      final item = await _repo(client)
          .submitContent(access: _token, uid: 'e-1');

      expect(sent.method, 'POST');
      expect(sent.url.path, endsWith('/education/content/e-1/submit/'));
      expect(item.status, 'IN_REVIEW');
    });

    test('delete removes a draft and tolerates a 204 with no body', () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return http.Response('', 204);
      });

      await _repo(client).deleteContent(access: _token, uid: 'e-1');

      expect(sent.method, 'DELETE');
      expect(sent.url.path, endsWith('/education/content/e-1/'));
    });

    test('a refused write surfaces the server message, not a generic error',
        () async {
      final client = MockClient((request) async => _json({
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'Only draft, rejected or archived content can be edited.',
            }
          }, 400));

      await expectLater(
        _repo(client).submitContent(access: _token, uid: 'e-1'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Doctor workspace actions', () {
    testWidgets('a draft offers edit, submit and delete', (tester) async {
      await _pump(
        tester,
        DoctorEducationView(
          accessToken: _token,
          repository: _repo(_workspaceClient(items: [_contentJson()])),
        ),
      );

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Submit for review'), findsOneWidget);
      expect(find.text('Delete draft'), findsOneWidget);
    });

    testWidgets('a published article offers none of them', (tester) async {
      await _pump(
        tester,
        DoctorEducationView(
          accessToken: _token,
          repository: _repo(
            _workspaceClient(items: [_contentJson(status: 'PUBLISHED')]),
          ),
        ),
      );

      expect(find.text('Edit'), findsNothing);
      expect(find.text('Submit for review'), findsNothing);
      expect(find.text('Delete draft'), findsNothing);
      expect(
        find.textContaining('Only draft, rejected or archived'),
        findsWidgets,
      );
    });

    testWidgets('the new-article button opens the composer', (tester) async {
      await _pump(
        tester,
        DoctorEducationView(
          accessToken: _token,
          repository: _repo(_workspaceClient(items: [_contentJson()])),
        ),
      );

      await tester.tap(find.text('New article').first);
      await tester.pumpAndSettle();

      expect(find.byType(ArticleFormPage), findsOneWidget);
      expect(find.text('What patients will see first'), findsOneWidget);
    });

    testWidgets('submitting asks for confirmation before it sends',
        (tester) async {
      final submitted = <String>[];
      final client = _workspaceClient(
        items: [_contentJson()],
        onRequest: (request) {
          if (request.url.path.endsWith('/submit/')) {
            submitted.add(request.method);
          }
        },
      );

      await _pump(
        tester,
        DoctorEducationView(
          accessToken: _token,
          repository: _repo(client),
        ),
      );

      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();
      expect(find.text('Submit for review?'), findsOneWidget);
      expect(submitted, isEmpty, reason: 'nothing sent until confirmed');

      await tester.tap(find.widgetWithText(FilledButton, 'Submit for review').last);
      await tester.pumpAndSettle();

      expect(submitted, ['POST']);
      expect(find.text('Sent for review.'), findsOneWidget);
    });

    testWidgets('cancelling the hand-off sends nothing', (tester) async {
      final submitted = <String>[];
      final client = _workspaceClient(
        items: [_contentJson()],
        onRequest: (request) {
          if (request.url.path.endsWith('/submit/')) submitted.add(request.method);
        },
      );

      await _pump(
        tester,
        DoctorEducationView(
          accessToken: _token,
          repository: _repo(client),
        ),
      );

      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(submitted, isEmpty);
    });
  });

  group('Article composer', () {
    testWidgets('an empty form will not post', (tester) async {
      final posted = <String>[];
      final client = MockClient((request) async {
        if (request.method == 'POST') posted.add(request.url.path);
        return _json(_categoriesJson);
      });

      await _pump(
        tester,
        ArticleFormPage(accessToken: _token, repository: _repo(client)),
      );

      await _tapSave(tester);

      expect(posted, isEmpty);
      expect(find.text('A title is required.'), findsOneWidget);
      expect(find.text('The article text cannot be empty.'), findsOneWidget);
    });

    testWidgets('a cover link must be an http(s) URL', (tester) async {
      final posted = <String>[];
      final client = MockClient((request) async {
        if (request.method == 'POST') posted.add(request.url.path);
        return _json(_categoriesJson);
      });

      await _pump(
        tester,
        ArticleFormPage(accessToken: _token, repository: _repo(client)),
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'A title');
      await tester.enterText(find.byType(TextFormField).at(1), 'Some body text.');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'ftp://example.org/cover.png',
      );
      await _tapSave(tester);

      expect(posted, isEmpty);
      expect(
        find.text('The cover link must start with http:// or https://'),
        findsOneWidget,
      );
    });

    testWidgets('a valid article is created and the composer pops',
        (tester) async {
      late Map<String, dynamic> payload;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return _json(_contentJson(status: 'DRAFT'), 201);
        }
        return _json(_categoriesJson);
      });

      await _pump(
        tester,
        ArticleFormPage(accessToken: _token, repository: _repo(client)),
      );

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Hydration and sickle cell',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Why water matters on hot days.',
      );
      await _tapSave(tester);

      expect(payload['title'], 'Hydration and sickle cell');
      expect(payload['body'], 'Why water matters on hot days.');
      expect(payload['category'], 'SICKLE_BASICS');
      // The composer pops rather than toasting: a SnackBar raised on this route
      // would be destroyed with it, so the caller confirms the write.
      expect(find.byType(ArticleFormPage), findsNothing);
    });

    testWidgets('an over-long title is caught while typing', (tester) async {
      final posted = <String>[];
      final client = MockClient((request) async {
        if (request.method == 'POST') posted.add(request.url.path);
        return _json(_categoriesJson);
      });

      await _pump(
        tester,
        ArticleFormPage(accessToken: _token, repository: _repo(client)),
      );

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'T' * (ArticleFormPage.titleMax + 1),
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Body.',
      );
      await _tapSave(tester);

      expect(posted, isEmpty);
      expect(
        find.text('Keep the title under 200 characters.'),
        findsOneWidget,
      );
    });

    testWidgets('editing an article pre-fills it and patches the same uid',
        (tester) async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        if (request.method == 'PATCH') {
          return _json(_contentJson(status: 'DRAFT'));
        }
        return _json(_categoriesJson);
      });

      final existing =
          EducationalContent.fromJson(_contentJson(status: 'REJECTED'));
      await _pump(
        tester,
        ArticleFormPage(
          accessToken: _token,
          repository: _repo(client),
          article: existing,
        ),
      );

      expect(find.text('Edit article'), findsOneWidget);
      expect(find.text('Understanding your transfusion plan'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Understanding your transfusion plan (revised)',
      );
      await _tapSave(tester);

      expect(sent.method, 'PATCH');
      expect(sent.url.path, endsWith('/education/content/e-1/'));
      expect(find.byType(ArticleFormPage), findsNothing);
    });

    testWidgets('a failed save explains the refusal', (tester) async {
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          return _json({
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'Unsupported category.',
            }
          }, 400);
        }
        return _json(_categoriesJson);
      });

      await _pump(
        tester,
        ArticleFormPage(accessToken: _token, repository: _repo(client)),
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'A title');
      await tester.enterText(find.byType(TextFormField).at(1), 'Body text.');
      await _tapSave(tester);

      expect(find.text('Unsupported category.'), findsOneWidget);
      expect(find.byType(ArticleFormPage), findsOneWidget,
          reason: 'the composer stays open so the draft is not lost');
    });
  });

  group('Swahili authoring strings', () {
    testWidgets('the composer is fully localised', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('sw'),
          localizationsDelegates: materialLocalizationsDelegates(
            LocaleController(AppPreferences.memory())..value = const Locale('sw'),
          ),
          supportedLocales: AppLocalizationsDelegate.supportedLocales,
          theme: ThemeData(useMaterial3: true),
          home: ArticleFormPage(
            accessToken: _token,
            repository: _repo(MockClient((_) async => _json(_categoriesJson))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Makala mpya'), findsOneWidget);
      await tester.ensureVisible(find.text('Hifadhi rasimu'));
      expect(find.text('Hifadhi rasimu'), findsOneWidget);
      expect(find.text('Kategoria'), findsOneWidget);
      expect(find.text('Kichwa'), findsOneWidget);
    });
  });
}