/// Clinic appointment tests (§11).
///
/// Run::
///   flutter test test/clinic_appointments_test.dart
///
/// Covers the booking surface: the calendar reads the server-scoped list, a
/// visit is booked against a *verified* facility uid (never a typed name), a
/// slot in the past is refused before the request goes out, cancelling demands a
/// reason because the server records one, and a closed visit offers nothing.
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
import 'package:sicklers_warriors/features/clinic/data/appointments_repository.dart';
import 'package:sicklers_warriors/features/doctor_network/data/doctor_directory_repository.dart';
import 'package:sicklers_warriors/features/clinic/presentation/pages/appointment_detail_page.dart';
import 'package:sicklers_warriors/features/clinic/presentation/pages/appointment_form_page.dart';
import 'package:sicklers_warriors/features/clinic/presentation/pages/clinic_page.dart';

const _token = 'test-access';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> _appointmentJson({
  String uid = 'apt-1',
  String status = 'CONFIRMED',
  String appointmentType = 'FOLLOW_UP',
  String scheduledAt = '2099-04-02T09:00:00Z',
}) =>
    {
      'uid': uid,
      'patient_uid': 'pat-1',
      'facility': {
        'uid': 'fac-1',
        'name': 'Korle Bu Teaching Hospital',
        'region': 'Greater Accra',
        'city': 'Accra',
      },
      'facility_name': 'Korle Bu Teaching Hospital',
      'facility_region': 'Greater Accra',
      'facility_city': 'Accra',
      'doctor_uid': 'doc-1',
      'doctor_name': 'Dr. Mensah',
      'appointment_type': appointmentType,
      'status': status,
      'scheduled_at': scheduledAt,
      'duration_minutes': 30,
      'reason': 'Routine review',
      'follow_up_required': false,
      'reminder_enabled': true,
      'reminder_days_before': [1],
      'reminder_times': ['07:00'],
      'reminder_channels': ['in_app'],
      'reminders_sent': 0,
      'cancellation_reason': '',
      'booked_by_role': 'PATIENT',
      'is_past': false,
    };

const _facilityJson = {
  'uid': 'fac-1',
  'name': 'Korle Bu Teaching Hospital',
  'facility_type': 'HOSPITAL',
  'region': 'Greater Accra',
  'city': 'Accra',
  'is_verified': true,
};

const _facilitiesJson = {
  'count': 2,
  'results': [
    {
      'uid': 'fac-1',
      'name': 'Korle Bu Teaching Hospital',
      'facility_type': 'HOSPITAL',
      'region': 'Greater Accra',
      'city': 'Accra',
      'is_verified': true,
    },
    {
      'uid': 'fac-2',
      'name': 'Sickle Cell Centre',
      'facility_type': 'CLINIC',
      'region': 'Nairobi',
      'city': 'Nairobi',
      'is_verified': true,
    },
  ],
};

const _cliniciansJson = {
  'count': 2,
  'results': [
    {
      'uid': 'doc-1',
      'professional_type': 'DOCTOR',
      'display_name': 'Dr. Mensah',
      'specialty': 'Haematology',
      'registration_body': 'Ghana Medical Council',
      'facility': 'Korle Bu Teaching Hospital',
      'verification_status': 'APPROVED',
    },
    {
      'uid': 'doc-2',
      'professional_type': 'DOCTOR',
      'display_name': 'Dr. Owusu',
      'specialty': 'Paediatrics',
      'registration_body': 'Ghana Medical Council',
      'facility': 'Sickle Cell Centre',
      'verification_status': 'APPROVED',
    },
  ],
};

/// The verified registry the booking form reads for its clinician picker.
DoctorDirectoryRepository _registry([http.Client? client]) =>
    DoctorDirectoryRepository(
      tokenStore: EphemeralTokenStore(),
      client: client ?? MockClient((_) async => _json(_cliniciansJson)),
    );

AppointmentsRepository _repo(http.Client client) =>
    AppointmentsRepository(tokenStore: EphemeralTokenStore(), client: client);

/// Serves appointments, the verified-facility directory and every write.
http.Client _clinicClient({
  List<Map<String, dynamic>>? items,
  void Function(http.Request request)? onRequest,
}) =>
    MockClient((request) async {
      onRequest?.call(request);
      if (request.url.path.endsWith('/facilities/')) {
        return _json(_facilitiesJson);
      }
      // `/appointments/<uid>/` is a single visit, not the list envelope.
      if (request.method == 'GET' &&
          RegExp(r'/appointments/[^/]+/$').hasMatch(request.url.path)) {
        return _json(_appointmentJson());
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/status/')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(_appointmentJson(status: '${body['status']}'));
      }
      if (request.method == 'POST' || request.method == 'PATCH') {
        return _json(_appointmentJson(status: 'REQUESTED'), 201);
      }
      return _json({
        'count': items?.length ?? 0,
        'results': items ?? const <Map<String, dynamic>>[],
      });
    });

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

/// The submit button sits below the fold of the lazy form list, and the app bar
/// carries the same wording — so scroll it into view and tap the button itself.
Future<void> _tapBook(WidgetTester tester) async {
  final submit = find.widgetWithText(FilledButton, 'Book a visit');
  await tester.scrollUntilVisible(submit, 120, scrollable: find
          .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
          .first);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

/// Back to the top of the form: a validation message on the venue field sits
/// above the fold once the submit button has been scrolled to.
Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, 600));
  await tester.pumpAndSettle();
}

void main() {
  group('Appointment projection', () {
    test('an open visit is changeable; a closed one is not', () {
      for (final status in ['REQUESTED', 'CONFIRMED', 'RESCHEDULED']) {
        expect(
          ClinicAppointment.fromJson(_appointmentJson(status: status)).isOpen,
          isTrue,
          reason: status,
        );
      }
      for (final status in ['COMPLETED', 'CANCELLED', 'NO_SHOW']) {
        expect(
          ClinicAppointment.fromJson(_appointmentJson(status: status)).isOpen,
          isFalse,
          reason: status,
        );
      }
    });

    test('the facility uid is read from the nested projection', () {
      // `facility_uid` is write-only, so a list row only carries the nested
      // object; the uid has to be read from whichever shape arrived.
      final appointment = ClinicAppointment.fromJson(_appointmentJson());
      expect(appointment.facilityUid, 'fac-1');
      expect(appointment.facilityName, 'Korle Bu Teaching Hospital');
      expect(appointment.doctorName, 'Dr. Mensah');
    });
  });

  group('Clinic calendar', () {
    testWidgets('lists the server-scoped appointments', (tester) async {
      await _pump(
        tester,
        ClinicView(
          accessToken: _token,
          repository: _repo(_clinicClient(items: [
            _appointmentJson(),
            _appointmentJson(
              uid: 'apt-2',
              appointmentType: 'LAB_RESULTS',
              status: 'REQUESTED',
            ),
          ])),
        ),
      );

      expect(find.text('Follow-up visit'), findsOneWidget);
      expect(find.text('Laboratory results review'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Requested'), findsOneWidget);
    });

    testWidgets('shows an honest empty state', (tester) async {
      await _pump(
        tester,
        ClinicView(accessToken: _token, repository: _repo(_clinicClient())),
      );

      expect(find.textContaining('no appointments booked yet'), findsOneWidget);
      expect(find.text('Follow-up visit'), findsNothing);
    });

    testWidgets('the upcoming/past split is a server filter', (tester) async {
      final queries = <String?>[];
      await _pump(
        tester,
        ClinicView(
          accessToken: _token,
          repository: _repo(_clinicClient(
            onRequest: (request) =>
                queries.add(request.url.queryParameters['upcoming']),
          )),
        ),
      );
      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();

      expect(queries, ['1', '0']);
    });
  });

  group('Booking', () {
    testWidgets('offers only facilities the directory returned',
        (tester) async {
      await _pump(
        tester,
        AppointmentFormPage(
          accessToken: _token,
          repository: _repo(_clinicClient()),
          client: MockClient((_) async => _json(_facilitiesJson)),
          directoryRepository: _registry(),
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();

      // The selected entry is painted by the button and by the open menu.
      expect(
        find.text('Korle Bu Teaching Hospital · Accra, Greater Accra'),
        findsWidgets,
      );
      expect(find.text('Sickle Cell Centre · Nairobi, Nairobi'), findsOneWidget);
    });

    test('an unusable slot is refused before any request', () {
      final now = DateTime(2099, 4, 2, 10);
      // Today with an early hour: the date picker clamps the day, not the time.
      expect(
        appointmentScheduleProblem(DateTime(2099, 4, 2, 9), now),
        'clinic.inPast',
      );
      expect(appointmentScheduleProblem(null, now), 'clinic.pickDateTime');
      expect(appointmentScheduleProblem(now, now), isNull);
      expect(appointmentScheduleProblem(now.add(const Duration(minutes: 1)), now), isNull);
    });

    testWidgets('with several venues the patient must choose one',
        (tester) async {
      final posted = <String>[];
      await _pump(
        tester,
        AppointmentFormPage(
          accessToken: _token,
          repository: _repo(_clinicClient(
            onRequest: (request) {
              if (request.method == 'POST') posted.add(request.url.path);
            },
          )),
          client: MockClient((_) async => _json(_facilitiesJson)),
          directoryRepository: _registry(),
        ),
      );

      // Nothing is pre-selected when the directory lists several venues, so
      // the form refuses before it even looks at the slot.
      await _tapBook(tester);
      expect(posted, isEmpty);
      await _scrollToTop(tester);
      expect(find.text('Choose a verified clinic.'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sickle Cell Centre · Nairobi, Nairobi').last);
      await tester.pumpAndSettle();

      await _tapBook(tester);

      expect(posted, isEmpty);
      expect(find.text('Choose a date and time first.'), findsOneWidget);
    });

    testWidgets('a single verified venue is offered without a second tap',
        (tester) async {
      await _pump(
        tester,
        AppointmentFormPage(
          accessToken: _token,
          repository: _repo(_clinicClient()),
          client: MockClient((_) async => _json({
            'count': 1,
            'results': [_facilityJson],
          })),
          directoryRepository: _registry(),
        ),
      );

      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).first,
      );
      expect(dropdown.initialValue, 'fac-1');
    });

    testWidgets('the clinician comes from the verified registry',
        (tester) async {
      await _pump(
        tester,
        AppointmentFormPage(
          accessToken: _token,
          repository: _repo(_clinicClient()),
          client: MockClient((_) async => _json(_facilitiesJson)),
          directoryRepository: _registry(),
        ),
      );

      // There is no free-text uid field any more: a clinician is chosen from
      // the registry the server returned.
      expect(find.byType(TextField), findsOneWidget); // the reason field only
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();

      expect(find.text('Dr. Mensah · Haematology'), findsOneWidget);
      expect(find.text('Dr. Owusu · Paediatrics'), findsOneWidget);
      expect(find.textContaining('1234'), findsNothing);
    });

    test('the chosen clinician uid is what gets posted', () async {
      final directory = _registry();
      final clinicians = await directory.listPhysicians(access: _token);
      expect(clinicians.map((c) => c.uid), ['doc-1', 'doc-2']);

      late Map<String, dynamic> payload;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return _json(_appointmentJson(status: 'REQUESTED'), 201);
        }
        return _json(_facilitiesJson);
      });

      await _repo(client).book(
        access: _token,
        facilityUid: 'fac-1',
        scheduledAt: DateTime.utc(2099, 4, 2, 9).toIso8601String(),
        doctorUid: clinicians.first.uid,
      );
      expect(payload['doctor_uid'], 'doc-1');
    });

    test('a booked visit posts a verified facility uid', () async {
      late Map<String, dynamic> payload;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return _json(_appointmentJson(status: 'REQUESTED'), 201);
        }
        return _json(_facilitiesJson);
      });

      final appointment = await _repo(client).book(
        access: _token,
        facilityUid: 'fac-1',
        scheduledAt: DateTime.utc(2099, 4, 2, 9).toIso8601String(),
        appointmentType: 'LAB_RESULTS',
        reason: 'Repeat HbA2',
      );

      expect(payload['facility_uid'], 'fac-1');
      expect(payload['appointment_type'], 'LAB_RESULTS');
      expect(payload['reason'], 'Repeat HbA2');
      expect(appointment.status, 'REQUESTED');
    });

    test('a rejected booking surfaces the server message', () async {
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          return _json({
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'Choose a verified clinic or hospital.',
            }
          }, 400);
        }
        return _json(_facilitiesJson);
      });

      await expectLater(
        _repo(client).book(
          access: _token,
          facilityUid: 'fac-9',
          scheduledAt: DateTime.utc(2099, 4, 2, 9).toIso8601String(),
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Choose a verified clinic or hospital.',
          ),
        ),
      );
    });
  });

  group('Visit detail', () {
    testWidgets('an open visit offers cancel and reschedule',
        (tester) async {
      await _pump(
        tester,
        AppointmentDetailPage(
          accessToken: _token,
          repository: _repo(_clinicClient()),
          appointmentUid: 'apt-1',
        ),
      );

      expect(find.text('Cancel visit'), findsOneWidget);
      expect(find.text('Reschedule'), findsOneWidget);
      expect(find.text('Dr. Mensah'), findsOneWidget);
    });

    testWidgets('a cancelled visit offers neither', (tester) async {
      await _pump(
        tester,
        AppointmentDetailPage(
          accessToken: _token,
          repository: _repo(_clinicClient()),
          appointmentUid: 'apt-1',
        ),
      );

      // Re-open the same visit as cancelled: the server keeps its history but
      // the patient can no longer change it.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(
        tester,
        AppointmentDetailPage(
          accessToken: _token,
          repository: _repo(MockClient(
            (request) async => _json(_appointmentJson(status: 'CANCELLED')),
          )),
          appointmentUid: 'apt-1',
        ),
      );

      expect(find.text('Cancel visit'), findsNothing);
      expect(find.text('Reschedule'), findsNothing);
      expect(find.textContaining('can no longer be changed'), findsOneWidget);
    });

    testWidgets('cancelling without a reason sends nothing', (tester) async {
      final posted = <String>[];
      final client = _clinicClient(
        onRequest: (request) {
          if (request.method == 'POST') posted.add(request.url.path);
        },
      );

      await _pump(
        tester,
        AppointmentDetailPage(
          accessToken: _token,
          repository: _repo(client),
          appointmentUid: 'apt-1',
        ),
      );

      await tester.tap(find.text('Cancel visit'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this visit?'), findsOneWidget);

      // Save with an empty reason: the dialog must refuse locally.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(posted, isEmpty);
      expect(find.text('A reason is required to cancel.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Feeling better.');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(posted.single, endsWith('/status/'));
      expect(find.text('Visit cancelled.'), findsOneWidget);
    });
  });

  group('Swahili calendar', () {
    testWidgets('renders in Kiswahili', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('sw'),
          localizationsDelegates: materialLocalizationsDelegates(
            LocaleController(AppPreferences.memory())..value = const Locale('sw'),
          ),
          supportedLocales: AppLocalizationsDelegate.supportedLocales,
          theme: ThemeData(useMaterial3: true),
          home: ClinicView(
            accessToken: _token,
            repository: _repo(_clinicClient(items: [_appointmentJson()])),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kalenda ya kliniki'), findsOneWidget);
      expect(find.text('Zijazo'), findsOneWidget);
      expect(find.text('Imethibitishwa'), findsOneWidget);
      expect(find.text('Pandaa tembeleo'), findsWidgets);
    });
  });
}