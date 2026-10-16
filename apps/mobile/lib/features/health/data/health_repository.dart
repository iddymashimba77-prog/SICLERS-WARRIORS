import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';
import '../../medication/data/medication_repository.dart' show AdherenceBlock;

/// Approved Stage 4.6 client for `/api/symptoms/*`, `/api/symptom-types/*`,
/// `/api/health-timeline/` and `GET /api/patients/me/dashboard/`.

class SymptomType {
  const SymptomType({
    required this.code,
    required this.name,
    required this.isPainRelated,
  });

  factory SymptomType.fromJson(Map<String, dynamic> json) => SymptomType(
        code: json['code'] as String? ?? '',
        name: (json['name'] as String?) ?? '',
        isPainRelated: (json['is_pain_related'] as bool?) ?? false,
      );

  final String code;
  final String name;
  final bool isPainRelated;
}

class Symptom {
  const Symptom({
    required this.uid,
    required this.symptomTypeCode,
    required this.symptomTypeName,
    required this.painLevel,
    required this.triggers,
    required this.durationMinutes,
    required this.notes,
    required this.recordedAt,
  });

  factory Symptom.fromJson(Map<String, dynamic> json) => Symptom(
        uid: json['uid'] as String? ?? '',
        symptomTypeCode: json['symptom_type_code'] as String? ?? '',
        symptomTypeName: json['symptom_type_name'] as String?,
        painLevel: (json['pain_level'] as num?)?.toInt(),
        triggers: ((json['triggers'] as List?) ?? const []).cast<String>(),
        durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
        notes: (json['notes'] as String?) ?? '',
        recordedAt: json['recorded_at'] as String?,
      );

  final String uid;
  final String symptomTypeCode;
  final String? symptomTypeName;
  final int? painLevel;
  final List<String> triggers;
  final int? durationMinutes;
  final String notes;
  final String? recordedAt;
}

class TimelineEntry {
  const TimelineEntry({
    required this.eventType,
    required this.occurredAt,
    required this.summary,
    required this.payload,
  });

  factory TimelineEntry.fromJson(Map<String, dynamic> json) => TimelineEntry(
        eventType: (json['event_type'] as String?) ?? '',
        occurredAt: json['occurred_at'] as String?,
        summary: (json['summary'] as String?) ?? '',
        payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
      );

  final String eventType;
  final String? occurredAt;
  final String summary;
  final Map<String, dynamic> payload;
}

class DashboardMedication {
  const DashboardMedication({
    required this.uid,
    required this.name,
    required this.strength,
    required this.isActive,
    required this.dosesTodayExpected,
    required this.dosesTodayPending,
  });

  factory DashboardMedication.fromJson(Map<String, dynamic> json) {
    final doses = json['doses_today'] as Map<String, dynamic>?;
    return DashboardMedication(
      uid: json['uid'] as String? ?? '',
      name: (json['name'] as String?) ?? '',
      strength: (json['strength'] as String?) ?? '',
      isActive: (json['is_active'] as bool?) ?? true,
      dosesTodayExpected: (doses?['expected'] as num?)?.toInt() ?? 0,
      dosesTodayPending: (doses?['pending'] as num?)?.toInt() ?? 0,
    );
  }

  final String uid;
  final String name;
  final String strength;
  final bool isActive;
  final int dosesTodayExpected;
  final int dosesTodayPending;
}

class HealthDashboard {
  const HealthDashboard({
    required this.generatedAt,
    required this.activeMedCount,
    required this.dosesToday,
    required this.adherenceLast7,
    required this.recentSymptoms,
    required this.recentTimeline,
    required this.medicalList,
  });

  factory HealthDashboard.fromJson(Map<String, dynamic> json) {
    final meds = json['medications'] as Map<String, dynamic>? ?? const {};
    final dosesToday =
        meds['doses_today'] as Map<String, dynamic>? ?? const {};
    return HealthDashboard(
      generatedAt: json['generated_at'] as String?,
      activeMedCount: (meds['active_count'] as num?)?.toInt() ?? 0,
      dosesToday: {
        'expected': (dosesToday['expected'] as num?)?.toInt() ?? 0,
        'taken': (dosesToday['taken'] as num?)?.toInt() ?? 0,
        'pending': (dosesToday['pending'] as num?)?.toInt() ?? 0,
      },
      adherenceLast7: AdherenceBlock.fromJson(
          (json['adherence_last_7_days'] as Map<String, dynamic>?) ??
              const {}),
      recentSymptoms: ((json['recent_symptoms'] as List?) ?? const [])
          .map((e) => Symptom.fromJson(e as Map<String, dynamic>))
          .toList(),
      recentTimeline: ((json['recent_timeline'] as List?) ?? const [])
          .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      medicalList: ((meds['list'] as List?) ?? const [])
          .map((e) => DashboardMedication.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String? generatedAt;
  final int activeMedCount;
  final Map<String, int> dosesToday;
  final AdherenceBlock adherenceLast7;
  final List<Symptom> recentSymptoms;
  final List<TimelineEntry> recentTimeline;
  final List<DashboardMedication> medicalList;
}

/// Client for symptom-type vocab, symptom records, timeline and the dashboard.
class HealthRepository {
  HealthRepository({required this.tokenStore, http.Client? client})
      : _client = client ?? http.Client();

  final TokenStore tokenStore;
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
      final details = (err['details'] as Map<String, dynamic>?) ?? const {};
      final fieldErrors = <String, List<String>>{};
      details.forEach((field, msgs) {
        fieldErrors[field] = [for (final m in msgs is List ? msgs : [msgs]) '$m'];
      });
      return AuthException(
        (err['message'] as String?) ?? 'Request failed.',
        code: (err['code'] as String?) ?? 'API_ERROR',
        statusCode: res.statusCode,
        fieldErrors: fieldErrors,
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
  ///
  /// `data` is a map for single objects and paginated collections, but a flat
  /// list for the unpaginated vocabularies (`GET /api/symptom-types/`), so the
  /// shape is decided by the caller — it is never cast to a map here.
  dynamic _data(http.Response res) {
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return map['data'] ?? map;
  }

  Map<String, dynamic> _body(http.Response res) {
    final data = _data(res);
    if (data is Map<String, dynamic>) return data;
    // Single-object callers (POST /symptoms/, the dashboard) must never see a
    // collection; report it instead of crashing on a `List is not a Map` cast.
    throw const AuthException('Unexpected response from the server.',
        code: 'API_ERROR');
  }

  List<dynamic> _listPayload(http.Response res) {
    final data = _data(res);
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      final results = data['results'];
      if (results is List) return results;
    }
    return const [];
  }

  Future<List<SymptomType>> listSymptomTypes({required String access}) async {
    final res = await _client
        .get(_uri(['symptom-types']), headers: _headers(access))
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => SymptomType.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Symptom>> listSymptoms({required String access}) async {
    final res = await _client
        .get(_uri(['symptoms']), headers: _headers(access))
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => Symptom.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Stage 4.6 — verified prescriber reads one patient's symptom log
  /// (`GET /api/symptoms/?patient=<uid>`). The backend still denies this to
  /// patients and to users without the clinical gate.
  Future<List<Symptom>> listSymptomsForPatient({
    required String access,
    required String patientUid,
  }) async {
    final uri = _uri(['symptoms']).replace(
      queryParameters: {'patient': patientUid},
    );
    final res = await _client
        .get(uri, headers: _headers(access))
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => Symptom.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Symptom> recordSymptom({
    required String access,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _client
        .post(
          _uri(['symptoms']),
          headers: _headers(access),
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
    return Symptom.fromJson(_body(res));
  }

  Future<List<TimelineEntry>> fetchTimeline({required String access}) async {
    final res = await _client
        .get(_uri(['health-timeline']), headers: _headers(access))
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<HealthDashboard> fetchDashboard({required String access}) async {
    final res = await _client
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/patients/me/dashboard/'),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return HealthDashboard.fromJson(_body(res));
  }
}