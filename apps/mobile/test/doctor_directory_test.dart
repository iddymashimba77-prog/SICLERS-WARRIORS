/// Verified care directory tests (`FR-CARE-001`).
///
/// Run::
///   flutter test test/doctor_directory_test.dart
///
/// The registry is a read of `GET /doctors/`, which the server has already
/// narrowed to approved, active professionals. These tests pin the two things a
/// patient could be harmed by: a name appearing that the API did not send, and a
/// profession filter that quietly becomes a client-side guess.
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
import 'package:sicklers_warriors/features/doctor_network/data/doctor_directory_repository.dart';
import 'package:sicklers_warriors/features/doctor_network/presentation/pages/doctor_network_page.dart';

const _token = 'test-access';

Map<String, dynamic> _professional({
  String uid = 'd1',
  String type = 'DOCTOR',
  String name = 'Dr. Ama Mensah',
  String specialty = 'Haematology',
  String body = 'Ghana Medical Council',
  String? facility = 'Korle Bu Teaching Hospital',
}) =>
    {
      'uid': uid,
      'professional_type': type,
      'display_name': name,
      'specialty': specialty,
      'registration_body': body,
      'facility': facility,
      'verification_status': 'APPROVED',
    };

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

DoctorDirectoryRepository _repo(http.Client client) =>
    DoctorDirectoryRepository(tokenStore: EphemeralTokenStore(), client: client);

/// Serves the registry and records what the app asked for.
http.Client _directoryClient({
  List<Map<String, dynamic>>? results,
  void Function(http.Request request)? onRequest,
}) =>
    MockClient((request) async {
      onRequest?.call(request);
      if (request.url.path.endsWith('/doctors/')) {
        return _json({
          'count': results?.length ?? 0,
          'results': results ?? const <Map<String, dynamic>>[],
        });
      }
      return _json(_professional(), 200);
    });

Future<void> _pump(WidgetTester tester, Widget child, {Locale? locale}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: materialLocalizationsDelegates(
        LocaleController(AppPreferences.memory())..value = locale,
      ),
      supportedLocales: AppLocalizationsDelegate.supportedLocales,
      theme: ThemeData(useMaterial3: true),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Registry client', () {
    test('reads the public subset the server sends', () async {
      final professionals = await _repo(_directoryClient(results: [
        _professional(),
        _professional(
          uid: 'd2',
          type: 'PSYCHOLOGIST',
          name: 'Grace Mwangi',
          specialty: 'Clinical psychology',
          facility: 'Kenyatta Hospital',
        ),
      ])).list(access: _token);

      expect(professionals, hasLength(2));
      expect(professionals.first.uid, 'd1');
      expect(professionals.first.isPhysician, isTrue);
      expect(professionals.last.isPsychologist, isTrue);
      expect(professionals.last.subtitle, 'Grace Mwangi · Clinical psychology');
    });

    test('a profession is a server query, never a client-side guess', () async {
      final queries = <String?>[];
      final client = MockClient((request) async {
        queries.add(request.url.queryParameters['professional_type']);
        return _json({'count': 0, 'results': const <dynamic>[]});
      });

      await _repo(client).list(access: _token, professionalType: 'PSYCHOLOGIST');
      expect(queries.last, 'PSYCHOLOGIST');

      // No filter at all when the caller did not narrow the search.
      await _repo(client).list(access: _token);
      expect(queries.last, isNull);
    });

    test('a rejected filter surfaces the server message', () async {
      final client = MockClient((request) async => _json({
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'Unknown professional type.',
            }
          }, 400));

      await expectLater(
        _repo(client).list(access: _token, professionalType: 'WIZARD'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Unknown professional type.',
          ),
        ),
      );
    });

    test('booking asks for physicians only', () async {
      final queries = <String>[];
      final client = MockClient((request) async {
        queries.add(request.url.queryParameters['professional_type'] ?? '');
        return _json({'count': 0, 'results': const <dynamic>[]});
      });

      await _repo(client).listPhysicians(access: _token);
      expect(queries, ['DOCTOR']);
    });
  });

  group('Directory screen', () {
    testWidgets('lists exactly what the API returned', (tester) async {
      await _pump(
        tester,
        DoctorDirectoryView(
          accessToken: _token,
          repository: _repo(_directoryClient(results: [
            _professional(),
            _professional(
              uid: 'd3',
              type: 'PSYCHOLOGIST',
              name: 'Grace Mwangi',
              specialty: 'Clinical psychology',
              facility: null,
            ),
          ])),
        ),
      );

      expect(find.text('Dr. Ama Mensah'), findsOneWidget);
      expect(find.text('Grace Mwangi'), findsOneWidget);
      expect(find.byIcon(Icons.medical_services_outlined), findsOneWidget);
      expect(find.byIcon(Icons.psychology_outlined), findsOneWidget);
      // No contact details exist in this projection, so nothing can render one.
      expect(find.textContaining('@'), findsNothing);
    });

    testWidgets('the profession filter re-queries the server', (tester) async {
      final requested = <String?>[];
      await _pump(
        tester,
        DoctorDirectoryView(
          accessToken: _token,
          repository: _repo(_directoryClient(
            results: [
              _professional(),
              _professional(uid: 'd2', type: 'PSYCHOLOGIST', name: 'Grace Mwangi'),
            ],
            onRequest: (request) => requested.add(
              request.url.queryParameters['professional_type'],
            ),
          )),
        ),
      );
      expect(requested, [null]);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Psychologist'));
      await tester.pumpAndSettle();
      expect(requested, [null, 'PSYCHOLOGIST']);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Everyone'));
      await tester.pumpAndSettle();
      expect(requested, [null, 'PSYCHOLOGIST', null]);
    });

    testWidgets('an empty registry says so instead of inventing names',
        (tester) async {
      await _pump(
        tester,
        DoctorDirectoryView(
          accessToken: _token,
          repository: _repo(_directoryClient()),
        ),
      );

      expect(find.text('Verified care directory'), findsOneWidget);
      expect(find.textContaining('No verified professionals are listed yet'),
          findsOneWidget);
      expect(find.text('Dr. Ama Mensah'), findsNothing);
    });

    testWidgets('a failure offers a retry', (tester) async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts == 1) return _json({'detail': 'Service unavailable.'}, 503);
        return _json({'count': 1, 'results': [_professional()]});
      });

      await _pump(
        tester,
        DoctorDirectoryView(accessToken: _token, repository: _repo(client)),
      );
      expect(find.text('The care directory could not be loaded.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Dr. Ama Mensah'), findsOneWidget);
    });

    testWidgets('renders in Kiswahili', (tester) async {
      await _pump(
        tester,
        DoctorDirectoryView(
          accessToken: _token,
          repository: _repo(_directoryClient(results: [_professional()])),
        ),
        locale: const Locale('sw'),
      );

      expect(find.text('Orodha ya wafanyakazi'), findsOneWidget);
      expect(find.text('Daktari'), findsWidgets);
      expect(find.text('Mwanaisimu'), findsOneWidget);
      expect(find.text('Msaada wa kijamii'), findsOneWidget);
    });
  });
}