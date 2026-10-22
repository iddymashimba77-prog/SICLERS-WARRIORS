/// Psychology workspace client for `/api/psychology/*` (§2).
///
/// Read access is consent-scoped server-side; this client only passes the
/// bearer token and renders whatever the server returns — never widens scope.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

class PsychologyCaseloadEntry {
  const PsychologyCaseloadEntry({
    required this.patientUid,
    required this.patientName,
    required this.hasConsent,
    required this.consentScope,
    this.lastAppointmentAt,
    this.nextAppointmentAt,
  });

  factory PsychologyCaseloadEntry.fromJson(Map<String, dynamic> json) =>
      PsychologyCaseloadEntry(
        patientUid: json['patient_uid'] as String,
        patientName: (json['patient_name'] as String?) ?? '',
        hasConsent: (json['has_consent'] as bool?) ?? false,
        consentScope:
            ((json['consent_scope'] as List?) ?? const []).cast<String>(),
        lastAppointmentAt: json['last_appointment_at'] as String?,
        nextAppointmentAt: json['next_appointment_at'] as String?,
      );

  final String patientUid;
  final String patientName;
  final bool hasConsent;
  final List<String> consentScope;
  final String? lastAppointmentAt;
  final String? nextAppointmentAt;
}

class PsychologyAssessment {
  const PsychologyAssessment({
    required this.uid,
    required this.patientUid,
    required this.patientName,
    required this.authorName,
    required this.concerns,
    required this.impression,
    required this.riskLevel,
    required this.notes,
    required this.assessedAt,
  });

  factory PsychologyAssessment.fromJson(Map<String, dynamic> json) =>
      PsychologyAssessment(
        uid: json['uid'] as String,
        patientUid: (json['patient_uid'] as String?) ?? '',
        patientName: (json['patient_name'] as String?) ?? '',
        authorName: (json['author_name'] as String?) ?? '',
        concerns: ((json['concerns'] as List?) ?? const []).cast<String>(),
        impression: (json['impression'] as String?) ?? 'NONE',
        riskLevel: (json['risk_level'] as String?) ?? 'ROUTINE',
        notes: (json['notes'] as String?) ?? '',
        assessedAt: (json['assessed_at'] as String?) ?? '',
      );

  final String uid;
  final String patientUid;
  final String patientName;
  final String authorName;
  final List<String> concerns;
  final String impression;
  final String riskLevel;
  final String notes;
  final String assessedAt;
}

class PsychologyProgressNote {
  const PsychologyProgressNote({
    required this.uid,
    required this.patientUid,
    required this.patientName,
    required this.authorName,
    required this.note,
    required this.sessionAt,
    this.followUpAt,
  });

  factory PsychologyProgressNote.fromJson(Map<String, dynamic> json) =>
      PsychologyProgressNote(
        uid: json['uid'] as String,
        patientUid: (json['patient_uid'] as String?) ?? '',
        patientName: (json['patient_name'] as String?) ?? '',
        authorName: (json['author_name'] as String?) ?? '',
        note: (json['note'] as String?) ?? '',
        sessionAt: (json['session_at'] as String?) ?? '',
        followUpAt: json['follow_up_at'] as String?,
      );

  final String uid;
  final String patientUid;
  final String patientName;
  final String authorName;
  final String note;
  final String sessionAt;
  final String? followUpAt;
}

class PsychologyReferral {
  const PsychologyReferral({
    required this.uid,
    required this.patientName,
    required this.destination,
    required this.reason,
    required this.urgency,
    required this.status,
    required this.responsiblePerson,
    this.followUpAt,
  });

  factory PsychologyReferral.fromJson(Map<String, dynamic> json) =>
      PsychologyReferral(
        uid: json['uid'] as String,
        patientName: (json['patient_name'] as String?) ?? '',
        destination: (json['destination'] as String?) ?? '',
        reason: (json['reason'] as String?) ?? '',
        urgency: (json['urgency'] as String?) ?? 'ROUTINE',
        status: (json['status'] as String?) ?? 'REQUESTED',
        responsiblePerson: (json['responsible_person'] as String?) ?? '',
        followUpAt: json['follow_up_at'] as String?,
      );

  final String uid;
  final String patientName;
  final String destination;
  final String reason;
  final String urgency;
  final String status;
  final String responsiblePerson;
  final String? followUpAt;
}

/// Concern-domain codes served by the backend (`psychology.models`).
const List<String> psychologyConcernCodes = [
  'coping_with_chronic_illness',
  'pain_related_distress',
  'anxiety_symptoms',
  'depression_symptoms',
  'stigma',
  'bullying',
  'sleep_difficulties',
  'social_support',
  'family_relationships',
  'school_challenges',
  'workplace_challenges',
];

class PsychologyRepository {
  PsychologyRepository({required this.tokenStore, http.Client? client})
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

  Future<List<PsychologyCaseloadEntry>> caseload(
      {required String access}) async {
    final res = await _client
        .get(_uri(['psychology', 'caseload']), headers: _headers(access))
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => PsychologyCaseloadEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PsychologyAssessment>> listAssessments({
    required String access,
    String? patientUid,
    String? riskLevel,
  }) async {
    final uri = _uri(['psychology', 'assessments']).replace(queryParameters: {
      if (patientUid != null && patientUid.isNotEmpty) 'patient_uid': patientUid,
      if (riskLevel != null && riskLevel.isNotEmpty) 'risk_level': riskLevel,
    });
    final res =
        await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _listPayload(res)
        .map((e) => PsychologyAssessment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createAssessment({
    required String access,
    required String patientUid,
    required List<String> concerns,
    required String impression,
    required String riskLevel,
    required String notes,
  }) async {
    final res = await _client
        .post(
          _uri(['psychology', 'assessments']),
          headers: _headers(access),
          body: jsonEncode({
            'patient_uid': patientUid,
            'concerns': concerns,
            'impression': impression,
            'risk_level': riskLevel,
            'notes': notes,
          }),
        )
        .timeout(_timeout);
    _body(res);
  }

  Future<List<PsychologyProgressNote>> listNotes({
    required String access,
    String? patientUid,
  }) async {
    final uri = _uri(['psychology', 'notes']).replace(queryParameters: {
      if (patientUid != null && patientUid.isNotEmpty) 'patient_uid': patientUid,
    });
    final res =
        await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _listPayload(res)
        .map((e) => PsychologyProgressNote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createNote({
    required String access,
    required String patientUid,
    required String note,
    String? followUpAt,
  }) async {
    final res = await _client
        .post(
          _uri(['psychology', 'notes']),
          headers: _headers(access),
          body: jsonEncode({
            'patient_uid': patientUid,
            'note': note,
            if (followUpAt != null && followUpAt.isNotEmpty)
              'follow_up_at': followUpAt,
          }),
        )
        .timeout(_timeout);
    _body(res);
  }

  Future<List<PsychologyReferral>> listReferrals({
    required String access,
    String? status,
  }) async {
    final uri = _uri(['psychology', 'referrals']).replace(queryParameters: {
      if (status != null && status.isNotEmpty) 'status': status,
    });
    final res =
        await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _listPayload(res)
        .map((e) => PsychologyReferral.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createReferral({
    required String access,
    required String patientUid,
    required String destination,
    required String reason,
    required String urgency,
    String responsiblePerson = '',
    String? followUpAt,
  }) async {
    final res = await _client
        .post(
          _uri(['psychology', 'referrals']),
          headers: _headers(access),
          body: jsonEncode({
            'patient_uid': patientUid,
            'destination': destination,
            'reason': reason,
            'urgency': urgency,
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
          _uri(['psychology', 'referrals', uid]),
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
