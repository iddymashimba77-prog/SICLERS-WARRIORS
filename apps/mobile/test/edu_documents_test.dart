/// Doctor-side education handout tests (FR-EDU-005).
///
/// Run::
///   flutter test test/edu_documents_test.dart
///
/// Covers the mobile half of the attachment feature: the pre-flight checks
/// that keep a bad file off the network, the multipart upload itself, the
/// remove call, the "a live article is frozen" rule, and the handout card that
/// appears on a published article.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/l10n/app_localizations.dart';
import 'package:sicklers_warriors/core/l10n/locale_controller.dart';
import 'package:sicklers_warriors/core/prefs/app_preferences.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/domain/auth_types.dart';
import 'package:sicklers_warriors/features/education/data/education_repository.dart';
import 'package:sicklers_warriors/features/education/presentation/pages/doctor_education_page.dart';
import 'package:sicklers_warriors/features/education/presentation/pages/education_detail_page.dart';

const _token = 'test-access';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> _contentJson({
  String uid = 'e-1',
  String title = 'Understanding your transfusion plan',
  String status = 'DRAFT',
  String? documentUrl,
  String documentName = '',
  int? documentSize,
}) =>
    {
      'id': 1,
      'uid': uid,
      'author': {'uid': 'doc-1', 'display_name': 'Dr. Mensah'},
      'title': title,
      'body': 'A short explainer.',
      'category': {'id': 3, 'code': 'SICKLE_BASICS', 'name': 'Sickle basics'},
      'status': status,
      'cover_url': '',
      'published_at': null,
      'created_at': '2026-09-19T10:00:00Z',
      'is_author': true,
      'document_url': documentUrl,
      'document_name': documentName,
      'document_content_type': documentUrl == null ? '' : 'application/pdf',
      'document_size': documentSize,
    };

EducationRepository _repo(http.Client client) =>
    EducationRepository(tokenStore: EphemeralTokenStore(), client: client);

/// A one-byte file on disk — enough for `MultipartFile.fromPath`.
String _tempFile(String name, [List<int> bytes = const [0x25, 0x50, 0x44, 0x46]]) {
  final dir = Directory.systemTemp.createTempSync('sw-edu-');
  final file = File('${dir.path}/$name')..writeAsBytesSync(bytes);
  addTearDown(() => dir.deleteSync(recursive: true));
  return file.path;
}

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
  group('DocumentUpload pre-flight rules', () {
    test('accepts every extension the server allows', () {
      for (final ext in DocumentUpload.allowedExtensions) {
        final upload = DocumentUpload(
          path: '/tmp/handout.$ext',
          filename: 'handout.$ext',
          sizeBytes: 1024,
        );
        expect(upload.rejectionReason, isNull, reason: ext);
      }
    });

    test('rejects an executable and explains what is allowed', () {
      const upload = DocumentUpload(
        path: '/tmp/payload.exe',
        filename: 'payload.exe',
        sizeBytes: 10,
      );
      expect(upload.hasAllowedExtension, isFalse);
      expect(upload.rejectionReason, contains('PDF'));
    });

    test('rejects an empty file', () {
      const upload = DocumentUpload(
        path: '/tmp/empty.pdf',
        filename: 'empty.pdf',
        sizeBytes: 0,
      );
      expect(upload.rejectionReason, contains('empty'));
    });

    test('rejects a file over 20 MB', () {
      final upload = DocumentUpload(
        path: '/tmp/big.pdf',
        filename: 'big.pdf',
        sizeBytes: DocumentUpload.maxBytes + 1,
      );
      expect(upload.isWithinSizeLimit, isFalse);
      expect(upload.rejectionReason, contains('20 MB'));
    });

    test('extension matching ignores case', () {
      const upload = DocumentUpload(
        path: '/tmp/HANDOUT.PDF',
        filename: 'HANDOUT.PDF',
        sizeBytes: 10,
      );
      expect(upload.extension, 'pdf');
      expect(upload.rejectionReason, isNull);
    });
  });

  group('EducationalContent document projection', () {
    test('maps the document fields and reports readable size', () {
      final item = EducationalContent.fromJson(_contentJson(
        status: 'PUBLISHED',
        documentUrl: 'https://api.example.org/media/education/documents/handout.pdf',
        documentName: 'handout.pdf',
        documentSize: 1536,
      ));
      expect(item.hasDocument, isTrue);
      expect(item.documentName, 'handout.pdf');
      expect(item.readableDocumentSize, '2 KB');
    });

    test('an article without a file reports no handout', () {
      final item = EducationalContent.fromJson(_contentJson());
      expect(item.hasDocument, isFalse);
      expect(item.documentName, '');
      expect(item.readableDocumentSize, '');
    });

    test('a published article is frozen for handout changes', () {
      expect(
        EducationalContent.fromJson(_contentJson(status: 'PUBLISHED'))
            .canChangeDocument,
        isFalse,
      );
      expect(
        EducationalContent.fromJson(_contentJson(status: 'DRAFT'))
            .canChangeDocument,
        isTrue,
      );
    });
  });

  group('EducationRepository document calls', () {
    test('listMyContent scopes the query to the author', () async {
      late Uri seen;
      final client = MockClient((request) async {
        seen = request.url;
        return _json({
          'count': 1,
          'results': [_contentJson(uid: 'mine-1')],
        });
      });
      final items = await _repo(client).listMyContent(access: _token);
      expect(seen.path, '/api/education/content/');
      expect(seen.queryParameters['mine'], '1');
      expect(items.single.uid, 'mine-1');
    });

    test('listMyContent forwards a status filter', () async {
      late Uri seen;
      final client = MockClient((request) async {
        seen = request.url;
        return _json({'count': 0, 'results': []});
      });
      await _repo(client).listMyContent(access: _token, status: 'DRAFT');
      expect(seen.queryParameters['status'], 'DRAFT');
    });

    test('uploadDocument posts multipart with a file part named document',
        () async {
      String? contentType;
      String? body;
      String? path;
      late String method;
      final client = MockClient((request) async {
        method = request.method;
        path = request.url.path;
        contentType = request.headers['content-type'];
        body = request.body;
        return _json(_contentJson(
          documentUrl: 'https://api.example.org/media/education/documents/x.pdf',
          documentName: 'x.pdf',
          documentSize: 3,
        ));
      });

      final item = await _repo(client).uploadDocument(
        access: _token,
        uid: 'e-1',
        upload: DocumentUpload(
          path: _tempFile('x.pdf'),
          filename: 'x.pdf',
          sizeBytes: 3,
        ),
      );

      expect(method, 'POST');
      expect(path, '/api/education/content/e-1/document/');
      expect(contentType, startsWith('multipart/form-data'));
      expect(contentType, contains('boundary='));
      expect(body, contains('name="document"'));
      expect(body, contains('filename="x.pdf"'));
      expect(item.hasDocument, isTrue);
    });

    test('uploadDocument surfaces the server rejection message', () async {
      final client = MockClient((request) async => _json({
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'That file is not a supported document.',
              'details': {'document': 'That file is not a supported document.'},
            }
          }, 400));
      await expectLater(
        _repo(client).uploadDocument(
          access: _token,
          uid: 'e-1',
          upload: DocumentUpload(
            path: _tempFile('x.pdf'),
            filename: 'x.pdf',
            sizeBytes: 3,
          ),
        ),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('not a supported document'),
        )),
      );
    });

    test('removeDocument deletes the document endpoint', () async {
      String? path;
      String? method;
      final client = MockClient((request) async {
        path = request.url.path;
        method = request.method;
        return _json(_contentJson());
      });
      final item = await _repo(client).removeDocument(access: _token, uid: 'e-7');
      expect(method, 'DELETE');
      expect(path, '/api/education/content/e-7/document/');
      expect(item.hasDocument, isFalse);
    });
  });

  group('DoctorEducationView', () {
    testWidgets('lists the author’s own articles including drafts',
        (tester) async {
      final client = MockClient((request) async => _json({
            'count': 2,
            'results': [
              _contentJson(uid: 'a-1', title: 'Draft one', status: 'DRAFT'),
              _contentJson(
                uid: 'a-2',
                title: 'Pending one',
                status: 'IN_REVIEW',
              ),
            ],
          }));
      await _pump(
        tester,
        DoctorEducationView(accessToken: _token, repository: _repo(client)),
      );

      expect(find.text('Draft one'), findsOneWidget);
      expect(find.text('Pending one'), findsOneWidget);
    });

    testWidgets('offers attach on a draft and no remove control yet',
        (tester) async {
      final client = MockClient((request) async => _json({
            'count': 1,
            'results': [_contentJson(status: 'DRAFT')],
          }));
      await _pump(
        tester,
        DoctorEducationView(accessToken: _token, repository: _repo(client)),
      );

      expect(find.text('Attach file'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
    });

    testWidgets('shows replace and remove once a file is attached',
        (tester) async {
      final client = MockClient((request) async => _json({
            'count': 1,
            'results': [
              _contentJson(
                status: 'DRAFT',
                documentUrl: 'https://api.example.org/media/x.pdf',
                documentName: 'x.pdf',
                documentSize: 2048,
              ),
            ],
          }));
      await _pump(
        tester,
        DoctorEducationView(accessToken: _token, repository: _repo(client)),
      );

      expect(find.text('Replace file'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.textContaining('x.pdf · 2 KB'), findsOneWidget);
    });

    testWidgets('locks the handout controls on a published article',
        (tester) async {
      final client = MockClient((request) async => _json({
            'count': 1,
            'results': [
              _contentJson(
                status: 'PUBLISHED',
                documentUrl: 'https://api.example.org/media/x.pdf',
                documentName: 'x.pdf',
              ),
            ],
          }));
      await _pump(
        tester,
        DoctorEducationView(accessToken: _token, repository: _repo(client)),
      );

      expect(find.text('Replace file'), findsNothing);
      expect(find.text('Remove'), findsNothing);
      expect(
        find.textContaining('Ask an administrator to unpublish'),
        findsOneWidget,
      );
    });

    testWidgets('asks before deleting a handout a patient already downloaded',
        (tester) async {
      var deletes = 0;
      final client = MockClient((request) async {
        if (request.method == 'DELETE') {
          deletes++;
          return _json(_contentJson(status: 'DRAFT'));
        }
        return _json({
          'count': 1,
          'results': [
            _contentJson(
              status: 'DRAFT',
              documentUrl: 'https://api.example.org/media/x.pdf',
              documentName: 'x.pdf',
            ),
          ],
        });
      });
      await _pump(
        tester,
        DoctorEducationView(accessToken: _token, repository: _repo(client)),
      );

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove handout?'), findsOneWidget);
      expect(deletes, 0, reason: 'must confirm before deleting');

      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
    });

    testWidgets('cancelling the dialog deletes nothing', (tester) async {
      var deletes = 0;
      final client = MockClient((request) async {
        if (request.method == 'DELETE') {
          deletes++;
          return _json(_contentJson(status: 'DRAFT'));
        }
        return _json({
          'count': 1,
          'results': [
            _contentJson(
              status: 'DRAFT',
              documentUrl: 'https://api.example.org/media/x.pdf',
              documentName: 'x.pdf',
            ),
          ],
        });
      });
      await _pump(
        tester,
        DoctorEducationView(accessToken: _token, repository: _repo(client)),
      );

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(deletes, 0);
    });

    testWidgets('filters the workspace by status', (tester) async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.query);
        return _json({'count': 0, 'results': []});
      });
      await _pump(
        tester,
        DoctorEducationView(accessToken: _token, repository: _repo(client)),
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Published'));
      await tester.pumpAndSettle();
      expect(paths.last, contains('status=PUBLISHED'));
    });

    testWidgets('surfaces a load failure with a retry', (tester) async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts == 1) return _json({'error': {'message': 'Boom'}}, 500);
        return _json({'count': 0, 'results': []});
      });
      await _pump(
        tester,
        DoctorEducationView(accessToken: _token, repository: _repo(client)),
      );

      expect(find.textContaining('Boom'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
    });
  });

  group('Published article handout card', () {
    testWidgets('shows a download entry only when a file is attached',
        (tester) async {
      final client = MockClient((request) async => _json(_contentJson(
            status: 'PUBLISHED',
            documentUrl: 'https://api.example.org/media/handout.pdf',
            documentName: 'handout.pdf',
            documentSize: 4096,
          )));
      await _pump(
        tester,
        EducationDetailView(
          accessToken: _token,
          repository: _repo(client),
          contentUid: 'e-1',
        ),
      );

      expect(find.text('Download handout'), findsOneWidget);
      expect(find.text('handout.pdf · 4 KB'), findsOneWidget);
    });

    testWidgets('hides the card when the article has no handout',
        (tester) async {
      final client =
          MockClient((request) async => _json(_contentJson(status: 'PUBLISHED')));
      await _pump(
        tester,
        EducationDetailView(
          accessToken: _token,
          repository: _repo(client),
          contentUid: 'e-1',
        ),
      );

      expect(find.text('Download handout'), findsNothing);
    });
  });
}