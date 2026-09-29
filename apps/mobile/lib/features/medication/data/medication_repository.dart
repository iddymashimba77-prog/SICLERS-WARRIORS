/// Approved Stage 4.6 API client for `/api/medications/*` and the dashboard
/// (`/api/patients/me/dashboard/`). Models mirror the approved
/// database-design rows (`medications`, `medication_schedules`,
/// `medication_events`) and the approved endpoint matrix.
///
/// Ownership + validation are enforced server-side (patient-only, own scope);
/// this client never crosses ownership.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

const List<String> medicationRoutes = [
  'ORAL',
  'TOPICAL',
  'INHALED',
  'INJECTION',
  'SUBLINGUAL',
  'SUPPOSITORY',
  'OTHER',
];

const List<String> medicationStatuses = ['TAKEN', 'MISSED', 'SKIPPED', 'SNOOZED'];

class MedicationSchedule {
  const MedicationSchedule({
    required this.uid,
    required this.timeOfDay,
    required this.daysOfWeek,
    required this.notes,
  });

  factory MedicationSchedule.fromJson(Map<String, dynamic> json) =>
      MedicationSchedule(
        uid: json['uid'] as String,
        timeOfDay: json['time_of_day'] as String,
        daysOfWeek:
            ((json['days_of_week'] as List?) ?? const []).cast<String>(),
        notes: (json['notes'] as String?) ?? '',
      );

  final String uid;
  final String timeOfDay;
  final List<String> daysOfWeek;
  final String notes;

  String get timeLabel {
    final t = DateTime.tryParse('1970-01-01T${timeOfDay}Z')?.toLocal();
    return t == null
        ? timeOfDay
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

class Medication {
  const Medication({
    required this.uid,
    required this.name,
    required this.genericName,
    required this.strength,
    required this.dosage,
    required this.route,
    required this.frequency,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.schedules,
    required this.createdAt,
  });

  factory Medication.fromJson(Map<String, dynamic> json) => Medication(
        uid: json['uid'] as String,
        name: (json['name'] as String?) ?? '',
        genericName: (json['generic_name'] as String?) ?? '',
        strength: (json['strength'] as String?) ?? '',
        dosage: (json['dosage'] as String?) ?? '',
        route: (json['route'] as String?) ?? 'ORAL',
        frequency: (json['frequency'] as String?) ?? '',
        startDate: json['start_date'] as String?,
        endDate: json['end_date'] as String?,
        isActive: (json['is_active'] as bool?) ?? true,
        schedules: ((json['schedules'] as List?) ?? const [])
            .map((e) => MedicationSchedule.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: json['created_at'] as String?,
      );

  final String uid;
  final String name;
  final String genericName;
  final String strength;
  final String dosage;
  final String route;
  final String frequency;
  final String? startDate;
  final String? endDate;
  final bool isActive;
  final List<MedicationSchedule> schedules;
  final String? createdAt;

  String get displayName => [
        if (name.isNotEmpty) name,
        if (strength.isNotEmpty) strength,
      ].join(' ');

  Map<String, dynamic> toJson() => {
        'name': name,
        'generic_name': genericName,
        'strength': strength,
        'dosage': dosage,
        'route': route,
        'frequency': frequency,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
      };
}

class MedicationEvent {
  const MedicationEvent({
    required this.id,
    required this.scheduleUid,
    required this.status,
    required this.takenAt,
    required this.note,
    required this.createdAt,
  });

  factory MedicationEvent.fromJson(Map<String, dynamic> json) => MedicationEvent(
        id: json['id'] as int? ?? 0,
        scheduleUid: json['schedule_uid'] as String? ?? '',
        status: (json['status'] as String?) ?? '',
        takenAt: json['taken_at'] as String?,
        note: (json['note'] as String?) ?? '',
        createdAt: json['created_at'] as String?,
      );

  final int id;
  final String scheduleUid;
  final String status;
  final String? takenAt;
  final String note;
  final String? createdAt;
}

class AdherenceBlock {
  const AdherenceBlock({
    required this.expected,
    required this.taken,
    required this.missed,
    required this.skipped,
    required this.snoozed,
    required this.nonAdherent,
    required this.adherencePct,
  });

  factory AdherenceBlock.fromJson(Map<String, dynamic> json) => AdherenceBlock(
        expected: (json['expected'] as num?)?.toInt() ?? 0,
        taken: (json['taken'] as num?)?.toInt() ?? 0,
        missed: (json['missed'] as num?)?.toInt() ?? 0,
        skipped: (json['skipped'] as num?)?.toInt() ?? 0,
        snoozed: (json['snoozed'] as num?)?.toInt() ?? 0,
        nonAdherent: (json['non_adherent'] as num?)?.toInt() ?? 0,
        adherencePct: (json['adherence_pct'] as num?)?.toDouble(),
      );

  final int expected;
  final int taken;
  final int missed;
  final int skipped;
  final int snoozed;
  final int nonAdherent;
  final double? adherencePct;
}

class MedicationStatsPerMed {
  const MedicationStatsPerMed({
    required this.uid,
    required this.name,
    required this.isActive,
    required this.block,
  });

  factory MedicationStatsPerMed.fromJson(Map<String, dynamic> json) =>
      MedicationStatsPerMed(
        uid: json['uid'] as String,
        name: (json['name'] as String?) ?? '',
        isActive: (json['is_active'] as bool?) ?? true,
        block: AdherenceBlock.fromJson(json),
      );

  final String uid;
  final String name;
  final bool isActive;
  final AdherenceBlock block;
}

class MedicationStats {
  const MedicationStats({
    required this.windowDays,
    required this.overall,
    required this.perMedication,
  });

  factory MedicationStats.fromJson(Map<String, dynamic> json) =>
      MedicationStats(
        windowDays: (json['window_days'] as num?)?.toInt() ?? 30,
        overall: AdherenceBlock.fromJson(
            (json['overall'] as Map<String, dynamic>?) ?? const {}),
        perMedication: ((json['per_medication'] as List?) ?? const [])
            .map((e) =>
                MedicationStatsPerMed.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final int windowDays;
  final AdherenceBlock overall;
  final List<MedicationStatsPerMed> perMedication;
}

/// Client for the approved medication endpoints.
class MedicationRepository {
  MedicationRepository({required this.tokenStore, http.Client? client})
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

  Map<String, dynamic> _body(http.Response res) {
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return (map['data'] as Map<String, dynamic>?) ?? map;
  }

  List<dynamic> _listPayload(http.Response res) {
    final payload = _body(res);
    final results = payload['results'];
    if (results is List) return results;
    return const [];
  }

  Future<List<Medication>> listMedications({required String access}) async {
    final res = await _client
        .get(_uri(['medications']), headers: _headers(access))
        .timeout(_timeout);
    final list = _listPayload(res);
    return list
        .map((e) => Medication.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Medication> createMedication({
    required String access,
    required Medication medication,
  }) async {
    final res = await _client
        .post(
          _uri(['medications']),
          headers: _headers(access),
          body: jsonEncode(medication.toJson()),
        )
        .timeout(_timeout);
    return Medication.fromJson(_body(res));
  }

  Future<Medication> updateMedication({
    required String access,
    required Medication medication,
  }) async {
    final res = await _client
        .patch(
          _uri(['medications', medication.uid]),
          headers: _headers(access),
          body: jsonEncode(medication.toJson()),
        )
        .timeout(_timeout);
    return Medication.fromJson(_body(res));
  }

  Future<void> stopMedication({required String access, required String uid}) async {
    final res = await _client
        .delete(_uri(['medications', uid]), headers: _headers(access))
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
  }

  Future<List<MedicationSchedule>> listSchedules({
    required String access,
    required String medicationUid,
  }) async {
    final res = await _client
        .get(
          _uri(['medications', medicationUid, 'schedule']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => MedicationSchedule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MedicationSchedule> createSchedule({
    required String access,
    required String medicationUid,
    required String timeOfDay,
    required List<String> daysOfWeek,
    String notes = '',
  }) async {
    final res = await _client
        .post(
          _uri(['medications', medicationUid, 'schedule']),
          headers: _headers(access),
          body: jsonEncode({
            'time_of_day': timeOfDay,
            'days_of_week': daysOfWeek,
            'notes': notes,
          }),
        )
        .timeout(_timeout);
    return MedicationSchedule.fromJson(_body(res));
  }

  Future<void> deleteSchedule({
    required String access,
    required String medicationUid,
    required String scheduleUid,
  }) async {
    final res = await _client
        .delete(
          _uri(['medications', medicationUid, 'schedule', scheduleUid]),
          headers: _headers(access),
        )
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
  }

  Future<MedicationEvent> logDose({
    required String access,
    required String medicationUid,
    required String scheduleUid,
    required String status,
    DateTime? takenAt,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ??
        '$medicationUid-$scheduleUid-${DateTime.now().microsecondsSinceEpoch}';
    final res = await _client
        .post(
          _uri(['medications', medicationUid, 'log-dose']),
          headers: {..._headers(access), 'Idempotency-Key': key},
          body: jsonEncode({
            'schedule': scheduleUid,
            'status': status,
            if (takenAt != null) 'taken_at': takenAt.toUtc().toIso8601String(),
          }),
        )
        .timeout(_timeout);
    return MedicationEvent.fromJson(_body(res));
  }

  Future<List<MedicationEvent>> listEvents({
    required String access,
    required String medicationUid,
  }) async {
    final res = await _client
        .get(
          _uri(['medications', medicationUid, 'events']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => MedicationEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MedicationStats> fetchStats({required String access}) async {
    final res = await _client
        .get(_uri(['medications', 'stats']), headers: _headers(access))
        .timeout(_timeout);
    return MedicationStats.fromJson(_body(res));
  }
}