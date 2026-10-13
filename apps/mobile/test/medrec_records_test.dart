/// Patient chart surface tests (FR-MEDREC-001/002/006).
///
/// Run::
///   flutter test test/medrec_records_test.dart
///
/// Covers the signed-in chart: the list reads the server-scoped read set with no
/// client-side widening, the list projection keeps clinical text out of the row,
/// attachments resolve through the authorized download path (never a link),
/// per-record visibility and status changes prompt for a reason and refresh,
/// and the append-only history renders for both one record and the whole chart.
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
import 'package:sicklers_warriors/features/auth/domain/auth_types.dart';
import 'package:sicklers_warriors/features/medical/data/medical_records_repository.dart';
import 'package:sicklers_warriors/features/medical/presentation/pages/medical_record_detail_page.dart';
import 'package:sicklers_warriors/features/medical/presentation/pages/medical_record_history_page.dart';
import 'package:sicklers_warriors/features/medical/presentation/pages/medical_records_page.dart';

const _token = 'test-access';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// The list projection deliberately omits `description`.
Map<String, dynamic> _summaryJson({
  String uid = 'rec-1',
  String title = 'Transfusion plan',
  String status = 'ACTIVE',
  String categoryName = 'Treatment',
  int fileCount = 0,
}) =>
    {
      'uid': uid,
      'title': title,
      'category_code': 'TREATMENT',
      'category_name': categoryName,
      'status': status,
      'is_consent_visible': true,
      'recorded_at': '2026-09-01T09:00:00Z',
      'facility_name': 'Korle Bu Teaching Hospital',
      'recorded_by_name': 'Dr. Mensah',
      'file_count': fileCount,
      'created_at': '2026-09-01T09:00:00Z',
      'updated_at': '2026-09-02T09:00:00Z',
    };

Map<String, dynamic> _detailJson({
  String uid = 'rec-1',
  String status = 'ACTIVE',
  bool canEdit = false,
  bool isConsentVisible = true,
  bool withFile = true,
}) =>
    {
      ..._summaryJson(uid: uid, status: status),
      'is_consent_visible': isConsentVisible,
      'description': 'Transfuse every 4 weeks to keep Hb above 9 g/dL.',
      'patient_uid': 'pat-1',
      'encounter_uid': null,
      'facility_uid': 'fac-1',
      'recorded_by_uid': 'doc-1',
      'can_edit': canEdit,
      'can_upload': canEdit,
      'files': withFile
          ? [
              {
                'uid': 'file-1',
                'file_name': 'plan.pdf',
                'content_type': 'application/pdf',
                'size_bytes': 2048,
                'checksum': 'abc',
                'uploaded_by_uid': 'doc-1',
                'uploaded_at': '2026-09-02T09:00:00Z',
                'download_path': '/api/medical-records/files/file-1/download/',
              }
            ]
          : [],
    };

Map<String, dynamic> _eventJson({
  String uid = 'ev-1',
  String eventType = 'record.created',
  String actorName = 'Dr. Mensah',
}) =>
    {
      'uid': uid,
      'record_uid': 'rec-1',
      'actor_uid': 'doc-1',
      'actor_name': actorName,
      'event_type': eventType,
      'from_status': null,
      'to_status': 'ACTIVE',
      'details': {'field': 'status'},
      'occurred_at': '2026-09-01T09:00:00Z',
    };

MedicalRecordsRepository _repo(http.Client client) =>
    MedicalRecordsRepository(tokenStore: EphemeralTokenStore(), client: client);

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
  group('Chart list', () {
    testWidgets('lists exactly what the API returned', (tester) async {
      final client = MockClient((request) async => _json({
            'count': 2,
            'results': [
              _summaryJson(uid: 'rec-1', title: 'Transfusion plan'),
              _summaryJson(
                uid: 'rec-2',
                title: 'Vaccination record',
                categoryName: 'Prevention',
                fileCount: 2,
              ),
            ],
          }));

      await _pump(
        tester,
        MedicalRecordsView(accessToken: _token, repository: _repo(client)),
      );

      expect(find.text('Transfusion plan'), findsOneWidget);
      expect(find.text('Vaccination record'), findsOneWidget);
      expect(find.text('2 attachment(s)'), findsOneWidget);
      // Once as the status filter chip, then once per row's status chip.
      expect(find.text('Active'), findsNWidgets(3));
    });

    testWidgets('never invents a record when the read set is empty',
        (tester) async {
      final client = MockClient((request) async =>
          _json({'count': 0, 'results': <dynamic>[]}));

      await _pump(
        tester,
        MedicalRecordsView(accessToken: _token, repository: _repo(client)),
      );

      expect(find.textContaining('No records are shared with you yet.'),
          findsOneWidget);
      expect(find.text('Transfusion plan'), findsNothing);
    });

    testWidgets('the list row carries no clinical text', (tester) async {
      // `description` is absent from the list projection by design, so a chart
      // note cannot leak into a list screen that was never opened.
      final client = MockClient((request) async => _json({
            'count': 1,
            'results': [_summaryJson()],
          }));

      await _pump(
        tester,
        MedicalRecordsView(accessToken: _token, repository: _repo(client)),
      );

      expect(find.textContaining('Transfuse every 4 weeks'), findsNothing);
    });

    testWidgets('a status filter is sent to the server, not applied locally',
        (tester) async {
      final queries = <String?>[];
      final client = MockClient((request) async {
        queries.add(request.url.queryParameters['status']);
        return _json({'count': 0, 'results': <dynamic>[]});
      });

      await _pump(
        tester,
        MedicalRecordsView(accessToken: _token, repository: _repo(client)),
      );
      await tester.tap(find.text('Draft'));
      await tester.pumpAndSettle();

      expect(queries, [null, 'DRAFT']);
    });

    testWidgets('a server refusal is shown, not an empty chart',
        (tester) async {
      final client = MockClient((request) async => _json({
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'Unknown status filter.',
            }
          }, 400));

      await _pump(
        tester,
        MedicalRecordsView(
          accessToken: _token,
          repository: _repo(client),
          initialStatus: 'BOGUS',
        ),
      );

      expect(find.text('Unknown status filter.'), findsOneWidget);
      expect(find.textContaining('No records are shared'), findsNothing);
    });
  });

  group('Record detail', () {
    testWidgets('shows the note, the facts and the attachment', (tester) async {
      final client = MockClient((request) async => _json(_detailJson()));

      await _pump(
        tester,
        MedicalRecordDetailPage(
          accessToken: _token,
          repository: _repo(client),
          recordUid: 'rec-1',
        ),
      );

      expect(
        find.textContaining('Transfuse every 4 weeks'),
        findsOneWidget,
      );
      expect(find.text('Dr. Mensah'), findsOneWidget);
      expect(find.text('Korle Bu Teaching Hospital'), findsOneWidget);
      expect(find.text('plan.pdf · 2 KB'), findsOneWidget);
    });

    testWidgets('a read-only record offers sharing but no status change',
        (tester) async {
      final client = MockClient((request) async => _json(_detailJson()));

      await _pump(
        tester,
        MedicalRecordDetailPage(
          accessToken: _token,
          repository: _repo(client),
          recordUid: 'rec-1',
        ),
      );

      expect(find.text('Shared through my consent'), findsOneWidget);
      // `can_edit` is false, so no status button is offered at all.
      expect(find.text('Active'), findsNothing);
    });

    testWidgets('opting out of the consent read set is confirmed first',
        (tester) async {
      final calls = <String>[];
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/visibility/')) {
          calls.add('${request.method} ${jsonDecode(request.body)}');
          return _json(_detailJson(isConsentVisible: false));
        }
        return _json(_detailJson());
      });

      await _pump(
        tester,
        MedicalRecordDetailPage(
          accessToken: _token,
          repository: _repo(client),
          recordUid: 'rec-1',
        ),
      );

      await tester.tap(find.text('Shared through my consent'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: 'nothing sent until confirmed');
      expect(find.text('Who can see this record'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(calls.single, startsWith('POST'));
      expect(calls.single, contains('is_consent_visible: false'));
      expect(find.text('Sharing updated.'), findsOneWidget);
      expect(find.text('Private to me'), findsOneWidget);
    });
  });

  group('History', () {
    testWidgets('a record trail renders each append-only entry',
        (tester) async {
      final client = MockClient((request) async => _json({
            'count': 2,
            'results': [
              _eventJson(uid: 'ev-1', eventType: 'record.created'),
              _eventJson(
                uid: 'ev-2',
                eventType: 'record.status_changed',
                actorName: 'Dr. Osei',
              ),
            ],
          }));

      await _pump(
        tester,
        MedicalRecordHistoryPage(
          accessToken: _token,
          repository: _repo(client),
          recordUid: 'rec-1',
          title: 'History',
        ),
      );

      expect(find.text('record.created'), findsOneWidget);
      expect(find.text('record.status_changed'), findsOneWidget);
      expect(find.text('By Dr. Osei'), findsOneWidget);
    });

    testWidgets('the chart-wide trail uses the chart endpoint', (tester) async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return _json({'count': 0, 'results': <dynamic>[]});
      });

      await _pump(
        tester,
        MedicalRecordHistoryPage(
          accessToken: _token,
          repository: _repo(client),
          title: 'Chart history',
        ),
      );

      expect(paths.single, '/api/medical-records/history/');
      expect(find.text('No chart activity to show yet.'), findsOneWidget);
    });

    testWidgets('a system actor is not shown as a person', (tester) async {
      final client = MockClient((request) async => _json({
            'count': 1,
            'results': [_eventJson(actorName: 'System')],
          }));

      await _pump(
        tester,
        MedicalRecordHistoryPage(
          accessToken: _token,
          repository: _repo(client),
          recordUid: 'rec-1',
          title: 'History',
        ),
      );

      expect(find.text('By the system'), findsOneWidget);
      expect(find.textContaining('By System'), findsNothing);
    });
  });

  group('Attachments', () {
    test('a server-supplied file name cannot escape the download folder', () {
      // `file_name` is untrusted input: a stored name must never be able to
      // traverse out of the directory it is written into.
      const hostile = MedicalRecordFile(
        uid: 'file-1',
        fileName: '../../../etc/passwd',
        contentType: 'text/plain',
        sizeBytes: 10,
        downloadPath: '/api/medical-records/files/file-1/download/',
      );
      expect(hostile.safeLocalName, 'passwd');
      expect(hostile.safeLocalName.contains('/'), isFalse);
    });

    test('an empty name still yields a usable local name', () {
      const blank = MedicalRecordFile(
        uid: 'file-9',
        fileName: '   ',
        contentType: '',
        sizeBytes: 0,
        downloadPath: '',
      );
      expect(blank.safeLocalName, 'record-file-file-9');
    });

    test('a download goes through the authorized path, not a link', () async {
      Uri? seen;
      final client = MockClient((request) async {
        seen = request.url;
        return http.Response.bytes([0x25, 0x50, 0x44, 0x46], 200);
      });

      const file = MedicalRecordFile(
        uid: 'file-1',
        fileName: 'plan.pdf',
        contentType: 'application/pdf',
        sizeBytes: 4,
        downloadPath: '/api/medical-records/files/file-1/download/',
      );
      final bytes = await _repo(client)
          .downloadFile(access: _token, file: file);

      expect(bytes, [0x25, 0x50, 0x44, 0x46]);
      expect(seen!.path, '/api/medical-records/files/file-1/download/');
      expect(seen!.query, isEmpty, reason: 'no token in the URL');
    });

    test('a refused download surfaces the server message', () async {
      final client = MockClient((request) async => _json({
            'error': {
              'code': 'CONSENT_REQUIRED',
              'message': 'This record is not shared with you.',
            }
          }, 403));

      await expectLater(
        _repo(client).downloadFile(
          access: _token,
          file: const MedicalRecordFile(
            uid: 'file-1',
            fileName: 'plan.pdf',
            contentType: 'application/pdf',
            sizeBytes: 4,
            downloadPath: '',
          ),
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'This record is not shared with you.',
          ),
        ),
      );
    });
  });

  group('Swahili chart', () {
    testWidgets('the chart renders in Kiswahili', (tester) async {
      final client = MockClient((request) async => _json({
            'count': 1,
            'results': [_summaryJson()],
          }));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('sw'),
          localizationsDelegates: materialLocalizationsDelegates(
            LocaleController(AppPreferences.memory())..value = const Locale('sw'),
          ),
          supportedLocales: AppLocalizationsDelegate.supportedLocales,
          theme: ThemeData(useMaterial3: true),
          home: MedicalRecordsView(
            accessToken: _token,
            repository: _repo(client),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kumbukumbu za afya yangu'), findsOneWidget);
      expect(find.text('Hali zote'), findsOneWidget);
      expect(find.text('Inafanya kazi'), findsNWidgets(2));
    });
  });
}