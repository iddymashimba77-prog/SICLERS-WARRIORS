/// Social-support workspace client for `/api/social/*` (§3).
///
/// Casework only — this client never touches money: `linkedWorkflow` is a
/// pointer to an existing campaign/donation workflow, rendered as plain text.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

class SocialCaseloadEntry {
  const SocialCaseloadEntry({
    required this.patientUid,
    required this.patientName,
    required this.hasConsent,
    required this.consentScope,
    required this.openCaseCount,
  });

  factory SocialCaseloadEntry.fromJson(Map<String, dynamic> json) =>
      SocialCaseloadEntry(
        patientUid: json['patient_uid'] as String,
        patientName: (json['patient_name'] as String?) ?? '',
        hasConsent: (json['has_consent'] as bool?) ?? false,
        consentScope:
            ((json['consent_scope'] as List?) ?? const []).cast<String>(),
        openCaseCount: (json['open_case_count'] as int?) ?? 0,
      );

  final String patientUid;
  final String patientName;
  final bool hasConsent;
  final List<String> consentScope;
  final int openCaseCount;
}

class SocialCase {
  const SocialCase({
    required this.uid,
    required this.patientUid,
    required this.patientName,
    required this.title,
    required this.status,
    required this.openedAt,
    required this.linkedWorkflow,
    this.closedAt,
  });

  factory SocialCase.fromJson(Map<String, dynamic> json) => SocialCase(
        uid: json['uid'] as String,
        patientUid: (json['patient_uid'] as String?) ?? '',
        patientName: (json['patient_name'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'NEW',
        openedAt: (json['opened_at'] as String?) ?? '',
        closedAt: json['closed_at'] as String?,
        linkedWorkflow: (json['linked_workflow'] as String?) ?? '',
      );

  final String uid;
  final String patientUid;
  final String patientName;
  final String title;
  final String status;
  final String openedAt;
  final String? closedAt;
  final String linkedWorkflow;
}

class SocialCaseNote {
  const SocialCaseNote({
    required this.uid,
    required this.authorName,
    required this.note,
    required this.createdAt,
  });

  factory SocialCaseNote.fromJson(Map<String, dynamic> json) => SocialCaseNote(
        uid: json['uid'] as String,
        authorName: (json['author_name'] as String?) ?? '',
        note: (json['note'] as String?) ?? '',
        createdAt: (json['created_at'] as String?) ?? '',
      );

  final String uid;
  final String authorName;
  final String note;
  final String createdAt;
}

class SocialNeedsAssessment {
  const SocialNeedsAssessment({
    required this.uid,
    required this.patientName,
    required this.needs,
    required this.observations,
    required this.assessedAt,
  });

  factory SocialNeedsAssessment.fromJson(Map<String, dynamic> json) =>
      SocialNeedsAssessment(
        uid: json['uid'] as String,
        patientName: (json['patient_name'] as String?) ?? '',
        needs: ((json['needs'] as List?) ?? const []).cast<String>(),
        observations: (json['observations'] as String?) ?? '',
        assessedAt: (json['assessed_at'] as String?) ?? '',
      );

  final String uid;
  final String patientName;
  final List<String> needs;
  final String observations;
  final String assessedAt;
}

class SocialReferral {
  const SocialReferral({
    required this.uid,
    required this.patientName,
    required this.destination,
    required this.reason,
    required this.status,
    required this.responsiblePerson,
    this.followUpAt,
    this.caseUid,
  });

  factory SocialReferral.fromJson(Map<String, dynamic> json) => SocialReferral(
        uid: json['uid'] as String,
        patientName: (json['patient_name'] as String?) ?? '',
        destination: (json['destination'] as String?) ?? '',
        reason: (json['reason'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'REQUESTED',
        responsiblePerson: (json['responsible_person'] as String?) ?? '',
        followUpAt: json['follow_up_at'] as String?,
        caseUid: json['case_uid'] as String?,
      );

  final String uid;
  final String patientName;
  final String destination;
  final String reason;
  final String status;
  final String responsiblePerson;
  final String? followUpAt;
  final String? caseUid;
}

/// Need-domain codes served by the backend (`social_work.models`).
const List<String> socialNeedCodes = [
  'food_security',
  'transport_to_care',
  'housing_living_situation',
  'income_employment',
  'family_caregiving',
  'school_work_support',
  'social_inclusion',
  'treatment_adherence',
];

class SocialWorkRepository {
  SocialWorkRepository({required this.tokenStore, http.Client? client})
      : _client = client ?? http.Client();

  final TokenStore tokenStore;
  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  Uri _uri(List<String> segments) =>
      Uri.parse('${AppConfig.apiBaseUrl}/${segments.join('/')}/');

  Map<String, String> _headers(String access) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $access',
      };

  AuthException _errorFrom(http.Response res, String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final err = map['error'] as Map<String, dynamic>? ?? const {};
      return AuthException(
        (err['message'] as String?) ?? 'Request failed.',
        code: (err['code'] as String?) ?? 'API_ERROR',
        statusCode: res.statusCode,
      );
    } catch (_) {
      return AuthException(
        res.statusCode >= 500
            ? 'Server error. Please try again shortly.'
            : 'Request failed (${res.statusCode}).',
        code: 'API_ERROR',
        statusCode: res.statusCode,
      );
    }
  }

  Map<String, dynamic> _body(http.Response res) {
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return (map['data'] as Map<String, dynamic>?) ?? map;
  }

  List<dynamic> _listPayload(http.Response res) {
    final payload = _body(res);
    final results = payload['results'];
    return results is List ? results : const [];
  }

  Future<List<SocialCaseloadEntry>> caseload({required String access}) async {
    final res = await _client
        .get(_uri(['social', 'caseload']), headers: _headers(access))
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => SocialCaseloadEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<SocialCase>> listCases({
    required String access,
    String? status,
    String? patientUid,
  }) async {
    final uri = _uri(['social', 'cases']).replace(queryParameters: {
      if (status != null && status.isNotEmpty) 'status': status,
      if (patientUid != null && patientUid.isNotEmpty) 'patient_uid': patientUid,
    });
    final res =
        await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _listPayload(res)
        .map((e) => SocialCase.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createCase({
    required String access,
    required String patientUid,
    required String title,
    String linkedWorkflow = '',
  }) async {
    final res = await _client
        .post(
          _uri(['social', 'cases']),
          headers: _headers(access),
          body: jsonEncode({
            'patient_uid': patientUid,
            'title': title,
            if (linkedWorkflow.isNotEmpty) 'linked_workflow': linkedWorkflow,
          }),
        )
        .timeout(_timeout);
    _body(res);
  }

  Future<SocialCase> getCase({required String access, required String uid}) async {
    final res = await _client
        .get(_uri(['social', 'cases', uid]), headers: _headers(access))
        .timeout(_timeout);
    return SocialCase.fromJson(_body(res));
  }

  Future<void> updateCaseStatus({
    required String access,
    required String uid,
    required String status,
  }) async {
    final res = await _client
        .patch(
          _uri(['social', 'cases', uid]),
          headers: _headers(access),
          body: jsonEncode({'status': status}),
        )
        .timeout(_timeout);
    _body(res);
  }

  Future<List<SocialCaseNote>> listCaseNotes({
    required String access,
    required String caseUid,
  }) async {
    final res = await _client
        .get(_uri(['social', 'cases', caseUid, 'notes']),
            headers: _headers(access))
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => SocialCaseNote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addCaseNote({
    required String access,
    required String caseUid,
    required String note,
  }) async {
    final res = await _client
        .post(
          _uri(['social', 'cases', caseUid, 'notes']),
          headers: _headers(access),
          body: jsonEncode({'note': note}),
        )
        .timeout(_timeout);
    _body(res);
  }

  Future<List<SocialNeedsAssessment>> listNeeds({required String access}) async {
    final res = await _client
        .get(_uri(['social', 'needs']), headers: _headers(access))
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => SocialNeedsAssessment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createNeeds({
    required String access,
    required String patientUid,
    required List<String> needs,
    required String observations,
  }) async {
    final res = await _client
        .post(
          _uri(['social', 'needs']),
          headers: _headers(access),
          body: jsonEncode({
            'patient_uid': patientUid,
            'needs': needs,
            'observations': observations,
          }),
        )
        .timeout(_timeout);
    _body(res);
  }

  Future<List<SocialReferral>> listReferrals({
    required String access,
    String? status,
  }) async {
    final uri = _uri(['social', 'referrals']).replace(queryParameters: {
      if (status != null && status.isNotEmpty) 'status': status,
    });
    final res =
        await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _listPayload(res)
        .map((e) => SocialReferral.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createReferral({
    required String access,
    required String patientUid,
    required String destination,
    required String reason,
    String responsiblePerson = '',
    String? caseUid,
    String? followUpAt,
  }) async {
    final res = await _client
        .post(
          _uri(['social', 'referrals']),
          headers: _headers(access),
          body: jsonEncode({
            'patient_uid': patientUid,
            'destination': destination,
            'reason': reason,
            if (caseUid != null) 'case_uid': caseUid,
            if (responsiblePerson.isNotEmpty)
              'responsible_person': responsiblePerson,
            if (followUpAt != null && followUpAt.isNotEmpty)
              'follow_up_at': followUpAt,
          }),
        )
        .timeout(_timeout);
    _body(res);
  }

  Future<void> updateReferral({
    required String access,
    required String uid,
    String? status,
    String? responsiblePerson,
  }) async {
    final res = await _client
        .patch(
          _uri(['social', 'referrals', uid]),
          headers: _headers(access),
          body: jsonEncode({
            if (status != null) 'status': status,
            if (responsiblePerson != null)
              'responsible_person': responsiblePerson,
          }),
        )
        .timeout(_timeout);
    _body(res);
  }
}
