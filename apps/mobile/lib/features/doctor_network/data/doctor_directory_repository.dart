import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

/// One entry in the verified professional registry (`GET /doctors/`).
///
/// The projection is the server's public subset: display name, specialty,
/// registration body and facility. There is no contact data, no licence number
/// and no patient relationship here, so this object is safe to show to any
/// authenticated patient — but it is *only* ever populated from the API, never
/// from a local fixture.
class VerifiedProfessional {
  const VerifiedProfessional({
    required this.uid,
    required this.professionalType,
    required this.displayName,
    required this.specialty,
    required this.registrationBody,
    this.facility,
  });

  factory VerifiedProfessional.fromJson(Map<String, dynamic> json) =>
      VerifiedProfessional(
        uid: (json['uid'] as String?) ?? '',
        professionalType: (json['professional_type'] as String?) ?? 'DOCTOR',
        displayName: (json['display_name'] as String?) ?? '',
        specialty: (json['specialty'] as String?) ?? '',
        registrationBody: (json['registration_body'] as String?) ?? '',
        facility: json['facility'] as String?,
      );

  final String uid;
  final String professionalType;
  final String displayName;
  final String specialty;
  final String registrationBody;
  final String? facility;

  bool get isPsychologist => professionalType == 'PSYCHOLOGIST';
  bool get isSocialSupport => professionalType == 'SOCIAL_SUPPORT';
  bool get isPhysician => professionalType == 'DOCTOR';

  /// `name · specialty`, falling back to whichever half exists so a registry
  /// entry without a specialty still reads as a name.
  String get subtitle {
    final parts = [displayName, specialty]
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.join(' · ');
  }
}


/// One immutable verification decision (`FR-DOC-006/007`).
///
/// The `Doctor` row only remembers the current status, so a rejected-then-
/// reapproved applicant would otherwise have no record of the first refusal.
/// `reason` is the reviewer's own justification and is shown verbatim: the
/// applicant is entitled to read it.
class DoctorVerificationDecision {
  const DoctorVerificationDecision({
    required this.uid,
    required this.decision,
    required this.actorName,
    required this.decidedAt,
    this.fromStatus = '',
    this.toStatus = '',
    this.reason = '',
    this.licenseNumber = '',
    this.details = const {},
  });

  factory DoctorVerificationDecision.fromJson(Map<String, dynamic> json) =>
      DoctorVerificationDecision(
        uid: (json['uid'] as String?) ?? '',
        decision: (json['decision'] as String?) ?? '',
        actorName: (json['actor_name'] as String?) ?? '',
        decidedAt: (json['decided_at'] as String?) ?? '',
        fromStatus: (json['from_status'] as String?) ?? '',
        toStatus: (json['to_status'] as String?) ?? '',
        reason: (json['reason'] as String?) ?? '',
        licenseNumber: (json['license_number'] as String?) ?? '',
        details: (json['details'] as Map<String, dynamic>?) ?? const {},
      );

  final String uid;
  final String decision;
  final String actorName;
  final String decidedAt;
  final String fromStatus;
  final String toStatus;
  final String reason;

  /// Registration number as held on the licence record. Kept out of the public
  /// directory projection; it appears here because the reader is either the
  /// applicant or a reviewer with `doctors.verify`.
  final String licenseNumber;
  final Map<String, dynamic> details;

  String get transition =>
      fromStatus.isEmpty ? toStatus : '$fromStatus → $toStatus';

  bool get isRejection => decision.toUpperCase().contains('REJECT');
}

/// The append-only trail plus the status it currently agrees with.
class DoctorVerificationHistory {
  const DoctorVerificationHistory({
    required this.doctorUid,
    required this.verificationStatus,
    required this.decisions,
  });

  factory DoctorVerificationHistory.fromJson(Map<String, dynamic> json) =>
      DoctorVerificationHistory(
        doctorUid: (json['doctor_uid'] as String?) ?? '',
        verificationStatus: (json['verification_status'] as String?) ?? '',
        decisions: [
          for (final row in (json['decisions'] as List<dynamic>? ?? const []))
            DoctorVerificationDecision.fromJson(row as Map<String, dynamic>),
        ],
      );

  final String doctorUid;
  final String verificationStatus;
  final List<DoctorVerificationDecision> decisions;

  bool get isEmpty => decisions.isEmpty;
}

/// The care-team registry, read-only (`FR-CARE-001`).
///
/// Only approved, active professionals reach this list: the server filters to
/// `verification_status=APPROVED, is_active=True`, so there is no client-side
/// "hide the unverified ones" pass that could ever be wrong. A clinician with no
/// registry entry cannot be selected anywhere in the app.
class DoctorDirectoryRepository {
  DoctorDirectoryRepository({required this.tokenStore, http.Client? client})
      : _client = client ?? http.Client();

  final TokenStore tokenStore;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  /// The server rejects an unknown `professional_type` with a 400, so the
  /// filters below are the complete set (doctors.PROFESSIONAL_TYPE_CODES).
  static const professionalTypes = <String>[
    'DOCTOR',
    'PSYCHOLOGIST',
    'SOCIAL_SUPPORT',
  ];

  Uri _uri(List<String> segments, [Map<String, String>? query]) => Uri.parse(
        '${AppConfig.apiBaseUrl}/${segments.join('/')}/',
      ).replace(queryParameters: (query == null || query.isEmpty) ? null : query);

  Map<String, String> _headers(String access) => {
        'Accept': 'application/json',
        'Authorization': 'Bearer $access',
      };

  AuthException _errorFrom(http.Response res) {
    var message = 'Request failed (${res.statusCode}).';
    var code = 'API_ERROR';
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final err = body['error'] as Map<String, dynamic>?;
      if (err != null) {
        message = (err['message'] as String?) ?? message;
        code = (err['code'] as String?) ?? code;
      } else if (body['detail'] != null) {
        message = body['detail'].toString();
      }
    } catch (_) {
      // A non-JSON error body (proxy timeout, HTML 502) is reported as-is.
    }
    return AuthException(message, code: code, statusCode: res.statusCode);
  }

  Map<String, dynamic> _body(http.Response res) {
    if (res.statusCode >= 400) throw _errorFrom(res);
    if (res.statusCode == 204 || res.body.isEmpty) return const {};
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return (map['data'] as Map<String, dynamic>?) ?? map;
  }

  List<dynamic> _list(http.Response res) {
    final results = _body(res)['results'];
    return results is List ? results : const [];
  }

  /// Every verified professional, or one profession when [professionalType] is
  /// given. Null means "no filter" — the registry holds more than one kind of
  /// professional now, and each kind is served by this same route.
  Future<List<VerifiedProfessional>> list({
    required String access,
    String? professionalType,
  }) async {
    final query = <String, String>{
      if (professionalType != null && professionalType.isNotEmpty)
        'professional_type': professionalType,
    };
    final res = await _client
        .get(_uri(['doctors'], query), headers: _headers(access))
        .timeout(_timeout);
    return _list(res)
        .map((e) => VerifiedProfessional.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The verified professionals a patient may book with, used by the clinic
  /// booking form so a clinician is picked from the registry instead of typed
  /// as a bare uid.
  Future<List<VerifiedProfessional>> listPhysicians({required String access}) =>
      list(access: access, professionalType: 'DOCTOR');


  /// The append-only verification trail for one professional (`FR-DOC-007`).
  ///
  /// Readable by the applicant themselves and by a reviewer holding
  /// `doctors.verify`; everyone else gets a 404 from the server so the route
  /// never confirms that a particular licence application exists.
  Future<DoctorVerificationHistory> verificationHistory({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['doctors', uid, 'verification-history']), headers: _headers(access))
        .timeout(_timeout);
    return DoctorVerificationHistory.fromJson(_body(res));
  }

  /// A single registry entry by its user uid.
  Future<VerifiedProfessional> get({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['doctors', uid]), headers: _headers(access))
        .timeout(_timeout);
    return VerifiedProfessional.fromJson(_body(res));
  }
}