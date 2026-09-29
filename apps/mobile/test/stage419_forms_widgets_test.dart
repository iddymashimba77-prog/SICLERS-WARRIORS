import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/blood_donation/data/blood_repository.dart';
import 'package:sicklers_warriors/features/blood_donation/presentation/pages/blood_donation_page.dart';
import 'package:sicklers_warriors/features/medication/data/medication_repository.dart';
import 'package:sicklers_warriors/features/medication/presentation/pages/medication_form_page.dart';
import 'package:sicklers_warriors/features/profile/data/profile_repository.dart';
import 'package:sicklers_warriors/features/profile/presentation/widgets/patient_profile_form.dart';

const _token = 'test-access';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// Pushes a page and records the value its pop() resolves to — the canonical
/// way to observe "saved → popped" behaviour that keep-your-paper-trail apps use.
class _PageLauncher extends StatefulWidget {
  const _PageLauncher({required this.builder});

  final Widget Function() builder;

  @override
  State<_PageLauncher> createState() => _PageLauncherState();
}

class _PageLauncherState extends State<_PageLauncher> {
  bool? result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (result != null) Text('pop-result: $result'),
            FilledButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(builder: (_) => widget.builder()),
                );
                setState(() {});
              },
              child: const Text('open'),
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------------- *
 * A tall surface so the full PatientProfileForm (Save button) is on screen.  *
 * ------------------------------------------------------------------------- */
Future<void> _useTallViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('MedicationFormPage validation + submit (Stage 4.19)', () {
    testWidgets('requires name and frequency before any network call', (tester) async {
      var posted = false;
      final client = MockClient((request) async {
        posted = true;
        return _json({'data': {'uid': 'med-1', 'name': 'Hydroxyurea'}}, 201);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: _PageLauncher(
            builder: () => MedicationFormPage(
              accessToken: _token,
              repository: MedicationRepository(
                tokenStore: EphemeralTokenStore(),
                client: client,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, AppStrings.addMedication));
      await tester.pumpAndSettle();
      expect(posted, isFalse);
      expect(find.text('Required'), findsNWidgets(2));
    });

    testWidgets('a valid medication posts and pops true', (tester) async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return _json({
          'data': {
            'uid': 'med-1',
            'name': 'Hydroxyurea',
            'route': 'ORAL',
            'schedules': [],
          }
        }, 201);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: _PageLauncher(
            builder: () => MedicationFormPage(
              accessToken: _token,
              repository: MedicationRepository(
                tokenStore: EphemeralTokenStore(),
                client: client,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, AppStrings.medicationName),
        'Hydroxyurea',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, AppStrings.frequency),
        'daily',
      );
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.addMedication));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/api/medications/');
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['name'], 'Hydroxyurea');
      expect(body['frequency'], 'daily');
      expect(find.textContaining('pop-result: true'), findsOneWidget);
    });
  });

  group('PatientProfileForm validation (Stage 4.19)', () {
    testWidgets('rejects a malformed date of birth', (tester) async {
      await _useTallViewport(tester);
      PatientProfile? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PatientProfileForm(
                initial: const PatientProfile(),
                onSubmit: (p) async => submitted = p,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, AppStrings.dateOfBirth),
        '1995',
      );
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.save));
      await tester.pumpAndSettle();
      expect(find.text('Use YYYY-MM-DD'), findsWidgets);
      expect(submitted, isNull);
    });

    testWidgets('a valid form submits the collected medical identity',
        (tester) async {
      await _useTallViewport(tester);
      PatientProfile? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PatientProfileForm(
                initial: const PatientProfile(),
                onSubmit: (p) async => submitted = p,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, AppStrings.dateOfBirth),
        '1995-03-12',
      );
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.save));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      expect(submitted!.dateOfBirth, '1995-03-12');
      expect(find.text(AppStrings.saved), findsOneWidget);
    });
  });

  group('BloodRequestFormPage submit (Stage 4.19)', () {
    testWidgets('submits a blood request through the repository', (tester) async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return _json({
          'data': {
            'uid': 'br-1',
            'blood_group_needed': 'A+',
            'units': 1,
            'urgency': 'NORMAL',
            'status': 'PENDING_VERIFICATION',
          }
        }, 201);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: _PageLauncher(
            builder: () => BloodRequestFormPage(
              accessToken: _token,
              repository: BloodRepository(
                tokenStore: EphemeralTokenStore(),
                client: client,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, AppStrings.reasonForRequest),
        'Surgery next week',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, AppStrings.requestBlood));
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.requestBlood));
      await tester.pumpAndSettle();

      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/api/blood/requests/');
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['blood_group_needed'], 'A+');
      expect(body['reason'], 'Surgery next week');
      expect(captured!.headers['Idempotency-Key'], isNotEmpty);
      expect(find.text(AppStrings.bloodRequestCreated), findsOneWidget);
    });
  });
}