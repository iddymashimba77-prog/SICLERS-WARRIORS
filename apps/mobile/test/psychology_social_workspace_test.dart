import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/auth/domain/auth_types.dart';
import 'package:sicklers_warriors/features/auth/presentation/widgets/session_router.dart';
import 'package:sicklers_warriors/features/psychology/data/psychology_repository.dart';
import 'package:sicklers_warriors/features/social_work/data/social_work_repository.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content': 'application/json'},
    );

/// §2/§3: post-auth routing must land each verified professional in their own
/// workspace, and PENDING/REJECTED/SUSPENDED sessions in the status screen —
/// never the doctor shell, never a silent patient fallback.
void main() {
  group('SessionRouter — dedicated professional shells', () {
    test('APPROVED psychologist resolves to the psychology shell', () {
      final ctx = SessionRouter.resolve(
        roles: ['PSYCHOLOGIST'],
        doctorVerificationStatus: 'APPROVED',
      );
      expect(ctx, isNotNull);
      expect(ctx!.route, '/psychology-shell');
      expect(ctx.id, 'psychologist');
    });

    test('APPROVED social-support resolves to the social shell', () {
      final ctx = SessionRouter.resolve(
        roles: ['SOCIAL_SUPPORT'],
        doctorVerificationStatus: 'APPROVED',
      );
      expect(ctx, isNotNull);
      expect(ctx!.route, '/social-shell');
      expect(ctx.id, 'social-support');
    });

    test('non-approved professionals land on the verification status screen',
        () {
      for (final status in <String?>[null, 'PENDING', 'REJECTED', 'SUSPENDED']) {
        final psych = SessionRouter.resolve(
          roles: ['PSYCHOLOGIST'],
          doctorVerificationStatus: status,
        );
        expect(psych?.route, '/doctor-status', reason: 'status=$status');

        final social = SessionRouter.resolve(
          roles: ['SOCIAL_SUPPORT'],
          doctorVerificationStatus: status,
        );
        expect(social?.route, '/doctor-status', reason: 'status=$status');
      }
    });

    test('a doctor still resolves to the doctor shell when approved', () {
      final ctx = SessionRouter.resolve(
        roles: ['DOCTOR'],
        doctorVerificationStatus: 'APPROVED',
      );
      expect(ctx?.route, '/doctor-shell');
    });

    test('multi-role sessions still require Continue-as selection', () {
      final ctx = SessionRouter.resolve(
        roles: ['PSYCHOLOGIST', 'PATIENT'],
        doctorVerificationStatus: 'APPROVED',
      );
      expect(ctx, isNull);
    });
  });

  group('PsychologyRepository', () {
    late List<http.Request> seen;

    PsychologyRepository repo(http.Response Function(http.Request) handle) {
      seen = <http.Request>[];
      return PsychologyRepository(
        tokenStore: EphemeralTokenStore(),
        client: MockClient((request) async {
          seen.add(request);
          return handle(request);
        }),
      );
    }

    test('caseload GETs /psychology/caseload/ with the bearer token', () async {
      final repository = repo((_) => _json({
            'data': {
              'results': [
                {
                  'patient_uid': 'pat-1',
                  'patient_name': 'Asha Juma',
                  'has_consent': true,
                  'consent_scope': ['psychology.assessments.read'],
                  'last_appointment_at': '2026-10-01T09:00:00Z',
                  'next_appointment_at': '2026-10-05T09:00:00Z',
                },
              ],
            },
          }));
      final rows =
          await repository.caseload(access: 'tok-123');
      expect(rows, hasLength(1));
      expect(rows.single.patientName, 'Asha Juma');
      expect(rows.single.hasConsent, isTrue);
      expect(rows.single.nextAppointmentAt, '2026-10-05T09:00:00Z');
      expect(seen.single.method, 'GET');
      expect(seen.single.url.path, endsWith('/psychology/caseload/'));
      expect(seen.single.headers['Authorization'], 'Bearer tok-123');
    });

    test('createNote carries the follow-up date when one is agreed', () async {
      final repository = repo((request) => _json({'data': {'uid': 'n-1'}}));
      await repository.createNote(
        access: 't',
        patientUid: 'pat-1',
        note: 'Reviewed coping plan.',
        followUpAt: '2026-11-01T00:00:00.000Z',
      );
      final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
      expect(body, {
        'patient_uid': 'pat-1',
        'note': 'Reviewed coping plan.',
        'follow_up_at': '2026-11-01T00:00:00.000Z',
      });
    });

    test('createAssessment posts the structured payload verbatim', () async {
      final repository = repo((request) => _json({'data': {'uid': 'a-1'}}));
      await repository.createAssessment(
        access: 't',
        patientUid: 'pat-1',
        concerns: const ['anxiety_symptoms'],
        impression: 'MILD',
        riskLevel: 'MONITOR',
        notes: 'Sleeps poorly before clinic days.',
      );
      final request = seen.single;
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/psychology/assessments/'));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body, {
        'patient_uid': 'pat-1',
        'concerns': ['anxiety_symptoms'],
        'impression': 'MILD',
        'risk_level': 'MONITOR',
        'notes': 'Sleeps poorly before clinic days.',
      });
    });

    test('referral status updates PATCH only the submitted fields', () async {
      final repository = repo((request) => _json({'data': <String, dynamic>{}}));
      await repository.updateReferral(
        access: 't',
        uid: 'ref-9',
        status: 'ACCEPTED',
      );
      final request = seen.single;
      expect(request.method, 'PATCH');
      expect(request.url.path, endsWith('/psychology/referrals/ref-9/'));
      expect(jsonDecode(request.body), {'status': 'ACCEPTED'});
    });

    test('error envelope surfaces the server message as AuthException', () async {
      final repository = repo((_) => _json({
            'error': {
              'code': 'consent_required',
              'message': 'No active consent for this patient.',
            },
          }, 403));
      await expectLater(
        repository.listAssessments(access: 't'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', 'consent_required')
              .having(
                  (e) => e.message, 'message', 'No active consent for this patient.'),
        ),
      );
    });
  });

  group('SocialWorkRepository', () {
    late List<http.Request> seen;

    SocialWorkRepository repo(http.Response Function(http.Request) handle) {
      seen = <http.Request>[];
      return SocialWorkRepository(
        tokenStore: EphemeralTokenStore(),
        client: MockClient((request) async {
          seen.add(request);
          return handle(request);
        }),
      );
    }

    test('listCases forwards the status filter', () async {
      final repository = repo((request) => _json({
            'data': {
              'results': [
                {
                  'uid': 'case-1',
                  'patient_uid': 'pat-1',
                  'patient_name': 'Neema',
                  'title': 'School fees follow-up',
                  'status': 'IN_PROGRESS',
                  'opened_at': '2026-10-02T08:00:00Z',
                  'linked_workflow': '',
                },
              ],
            },
          }));
      final rows = await repository.listCases(
        access: 't',
        status: 'IN_PROGRESS',
      );
      expect(rows.single.status, 'IN_PROGRESS');
      expect(seen.single.url.queryParameters['status'], 'IN_PROGRESS');
    });

    test('createCase sends the pointer field, never money fields', () async {
      final repository = repo((request) => _json({'data': {'uid': 'case-2'}}));
      await repository.createCase(
        access: 't',
        patientUid: 'pat-1',
        title: 'Transport to care',
        linkedWorkflow: 'campaign-mbeya-2026',
      );
      final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
      expect(body, {
        'patient_uid': 'pat-1',
        'title': 'Transport to care',
        'linked_workflow': 'campaign-mbeya-2026',
      });
      expect(body.keys, isNot(contains(anyOf('amount', 'money', 'price'))));
    });

    test('case status transitions PATCH the status only', () async {
      final repository = repo((request) => _json({'data': <String, dynamic>{}}));
      await repository.updateCaseStatus(
        access: 't',
        uid: 'case-1',
        status: 'AWAITING_REFERRAL',
      );
      expect(seen.single.method, 'PATCH');
      expect(seen.single.url.path, endsWith('/social/cases/case-1/'));
      expect(jsonDecode(seen.single.body), {'status': 'AWAITING_REFERRAL'});
    });

    test('case notes post to the nested endpoint', () async {
      final repository = repo((request) => _json({'data': {'uid': 'note-1'}}));
      await repository.addCaseNote(
        access: 't',
        caseUid: 'case-1',
        note: 'Visited home; transport arranged.',
      );
      final request = seen.single;
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/social/cases/case-1/notes/'));
      expect(jsonDecode(request.body),
          {'note': 'Visited home; transport arranged.'});
    });

    test('403 from the server becomes AuthException, not a crash', () async {
      final repository = repo((_) => _json({
            'error': {
              'code': 'permission_denied',
              'message': 'Consent required.',
            },
          }, 403));
      await expectLater(
        repository.caseload(access: 't'),
        throwsA(isA<AuthException>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('social referrals carry the agreed follow-up date', () async {
      final repository = repo((request) => _json({'data': {'uid': 'sr-1'}}));
      await repository.createReferral(
        access: 't',
        patientUid: 'pat-1',
        destination: 'District social welfare office',
        reason: 'School attendance support',
        responsiblePerson: 'Neema K.',
        followUpAt: '2026-11-10T00:00:00.000Z',
      );
      final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
      expect(body['follow_up_at'], '2026-11-10T00:00:00.000Z');
      expect(body['responsible_person'], 'Neema K.');
    });
  });
}
