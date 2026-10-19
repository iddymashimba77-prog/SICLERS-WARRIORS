import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/domain/auth_types.dart';
import '../../health/data/health_repository.dart' show Symptom;

/// Consent-gated caregiver health track client (FR-CG health / C14).
///
/// `GET /api/caregivers/me/health/` answers with three honest, non-error
/// states (`no_link`, `no_consent`, `ok`) plus per-section consent scopes,
/// and `POST /api/caregivers/me/health/observations/` logs an observation for
/// the LINKED patient under the `symptoms.create` scope. Caregivers never load
/// `/patients/me/dashboard/` — the backend 403s that surface for them.
class LinkedPatient {
  const LinkedPatient({
    required this.patientUid,
    required this.firstName,
    required this.lastName,
    required this.relationshipType,
  });

  factory LinkedPatient.fromJson(Map<String, dynamic> json) => LinkedPatient(
        patientUid: json['patient_uid'] as String? ?? '',
        firstName: json['first_name'] as String? ?? '',
        lastName: json['last_name'] as String? ?? '',
        relationshipType: json['relationship_type'] as String? ?? '',
      );

  final String patientUid;
  final String firstName;
  final String lastName;
  final String relationshipType;

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? 'Member' : full;
  }
}

class CaregiverMedication {
  const CaregiverMedication({
    required this.uid,
    required this.name,
    required this.strength,
    required this.dosage,
    required this.frequency,
    required this.isActive,
  });

  factory CaregiverMedication.fromJson(Map<String, dynamic> json) =>
      CaregiverMedication(
        uid: json['uid'] as String? ?? '',
        name: json['name'] as String? ?? '',
        strength: json['strength'] as String? ?? '',
        dosage: json['dosage'] as String? ?? '',
        frequency: json['frequency'] as String? ?? '',
        isActive: (json['is_active'] as bool?) ?? true,
      );

  final String uid;
  final String name;
  final String strength;
  final String dosage;
  final String frequency;
  final bool isActive;

  String get label => [name, strength].where((s) => s.isNotEmpty).join(' ');

  String get schedule => [dosage, frequency].where((s) => s.isNotEmpty).join(' · ');
}

/// The health-track payload: `reason` distinguishes no link / no consent /
/// ok, and every section is separately consent-gated — a caregiver with only
/// `patients.view` sees the link but neither symptoms nor medications.
class CaregiverHealthSummary {
  const CaregiverHealthSummary({
    required this.reason,
    required this.linkedPatient,
    required this.consentScope,
    required this.canViewSymptoms,
    required this.canViewMedications,
    required this.canLog,
    required this.symptoms,
    required this.medications,
  });

  factory CaregiverHealthSummary.fromJson(Map<String, dynamic> json) =>
      CaregiverHealthSummary(
        reason: json['reason'] as String? ?? 'no_link',
        linkedPatient: json['linked_patient'] is Map<String, dynamic>
            ? LinkedPatient.fromJson(
                json['linked_patient'] as Map<String, dynamic>)
            : null,
        consentScope:
            ((json['consent_scope'] as List?) ?? const []).cast<String>(),
        canViewSymptoms: (json['can_view_symptoms'] as bool?) ?? false,
        canViewMedications: (json['can_view_medications'] as bool?) ?? false,
        canLog: (json['can_log'] as bool?) ?? false,
        symptoms: ((json['symptoms'] as List?) ?? const [])
            .map((e) => Symptom.fromJson(e as Map<String, dynamic>))
            .toList(),
        medications: ((json['medications'] as List?) ?? const [])
            .map((e) => CaregiverMedication.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String reason;
  final LinkedPatient? linkedPatient;
  final List<String> consentScope;
  final bool canViewSymptoms;
  final bool canViewMedications;
  final bool canLog;
  final List<Symptom> symptoms;
  final List<CaregiverMedication> medications;

  bool get isOk => reason == 'ok';
}

class CaregiverHealthRepository {
  CaregiverHealthRepository({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  Uri _uri(List<String> segments) => Uri.parse(
        '${AppConfig.apiBaseUrl}/${segments.join('/')}/',
      );

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

  /// Unwraps the `{data: …}` envelope every success body is rendered with.
  Map<String, dynamic> _body(http.Response res) {
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] ?? map;
    if (data is Map<String, dynamic>) return data;
    throw const AuthException('Unexpected response from the server.',
        code: 'API_ERROR');
  }

  /// Linked patient's consent-gated health summary — `no_link`, `no_consent`
  /// and `ok` are distinct successful answers, never transport errors.
  Future<CaregiverHealthSummary> fetchHealth({required String access}) async {
    final res = await _client
        .get(
          _uri(['caregivers', 'me', 'health']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return CaregiverHealthSummary.fromJson(_body(res));
  }

  /// Log an observation for the linked patient (same payload contract as the
  /// patient's own `POST /api/symptoms/`, authorized by `symptoms.create`).
  Future<Symptom> logObservation({
    required String access,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _client
        .post(
          _uri(['caregivers', 'me', 'health', 'observations']),
          headers: _headers(access),
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
    return Symptom.fromJson(_body(res));
  }
}
