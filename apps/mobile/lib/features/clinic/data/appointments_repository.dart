import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

/// Clinic appointments (§11).
///
/// The list is already scoped by the server to the patients this account may
/// see — own, consented or assigned — so this client sends no patient filter and
/// never widens the read set. Booking takes a **facility uid**, because the
/// server refuses an unverified clinic; there is no facility name to guess with
/// and no hardcoded venue list.
class ClinicAppointment {
  const ClinicAppointment({
    required this.uid,
    required this.appointmentType,
    required this.status,
    required this.scheduledAt,
    this.facilityUid = '',
    this.facilityName = '',
    this.facilityCity = '',
    this.facilityRegion = '',
    this.doctorUid = '',
    this.doctorName = '',
    this.patientUid = '',
    this.reason = '',
    this.durationMinutes = 30,
    this.isPast = false,
    this.reminderEnabled = true,
    this.reminderDaysBefore = const [],
    this.reminderTimes = const [],
    this.reminderChannels = const [],
    this.cancellationReason = '',
    this.bookedByRole = '',
  });

  factory ClinicAppointment.fromJson(Map<String, dynamic> json) =>
      ClinicAppointment(
        uid: (json['uid'] as String?) ?? '',
        appointmentType: (json['appointment_type'] as String?) ?? 'FOLLOW_UP',
        status: (json['status'] as String?) ?? 'REQUESTED',
        scheduledAt: (json['scheduled_at'] as String?) ?? '',
        facilityUid:
            (json['facility_uid'] as String?) ?? _uidOf(json['facility']),
        facilityName: (json['facility_name'] as String?) ?? '',
        facilityCity: (json['facility_city'] as String?) ?? '',
        facilityRegion: (json['facility_region'] as String?) ?? '',
        doctorUid: (json['doctor_uid'] as String?) ?? '',
        doctorName: (json['doctor_name'] as String?) ?? '',
        patientUid: (json['patient_uid'] as String?) ?? '',
        reason: (json['reason'] as String?) ?? '',
        durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 30,
        isPast: (json['is_past'] as bool?) ?? false,
        reminderEnabled: (json['reminder_enabled'] as bool?) ?? true,
        reminderDaysBefore: [
          for (final d in (json['reminder_days_before'] as List<dynamic>? ??
              const []))
            (d as num).toInt(),
        ],
        reminderTimes: [
          for (final t in (json['reminder_times'] as List<dynamic>? ?? const []))
            t.toString(),
        ],
        reminderChannels: [
          for (final c in (json['reminder_channels'] as List<dynamic>? ??
              const []))
            c.toString(),
        ],
        cancellationReason: (json['cancellation_reason'] as String?) ?? '',
        bookedByRole: (json['booked_by_role'] as String?) ?? '',
      );

  /// `facility` travels as a nested object on the list and only `facility_uid`
  /// is writable, so the uid is read from whichever shape came back.
  static String _uidOf(dynamic facility) =>
      facility is Map<String, dynamic>
          ? ((facility['uid'] as String?) ?? '')
          : '';

  final String uid;
  final String appointmentType;
  final String status;
  final String scheduledAt;
  final String facilityUid;
  final String facilityName;
  final String facilityCity;
  final String facilityRegion;
  final String doctorUid;
  final String doctorName;
  final String patientUid;
  final String reason;
  final int durationMinutes;
  final bool isPast;
  final bool reminderEnabled;
  final List<int> reminderDaysBefore;
  final List<String> reminderTimes;
  final List<String> reminderChannels;
  final String cancellationReason;
  final String bookedByRole;

  bool get isOpen =>
      status == 'REQUESTED' || status == 'CONFIRMED' || status == 'RESCHEDULED';

  bool get isCancelled => status == 'CANCELLED';

  /// The bookable visit types the server accepts (appointments.APPOINTMENT_TYPES).
  static const appointmentTypes = <String>[
    'NEW_PATIENT',
    'FOLLOW_UP',
    'ROUTINE_REVIEW',
    'LAB_RESULTS',
    'MEDICATION_REVIEW',
    'VACCINATION',
    'OTHER',
  ];
}

class AppointmentsRepository {
  AppointmentsRepository({required this.tokenStore, http.Client? client})
      : _client = client ?? http.Client();

  final TokenStore tokenStore;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  Uri _uri(List<String> segments, [Map<String, String>? query]) => Uri.parse(
        '${AppConfig.apiBaseUrl}/${segments.join('/')}/',
      ).replace(queryParameters: (query == null || query.isEmpty) ? null : query);

  Map<String, String> _headers(String access) => {
        'Accept': 'application/json',
        'Authorization': 'Bearer $access',
      };

  Map<String, String> _writeHeaders(String access) => {
        ..._headers(access),
        'Content-Type': 'application/json',
      };

  AuthException _errorFrom(http.Response res) {
    String message = 'Request failed (${res.statusCode}).';
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
      final fields = body['errors'];
      if (fields is Map<String, dynamic> && fields.isNotEmpty) {
        // A field-level validation refusal is more useful than the envelope.
        final first = fields.entries.first;
        final detail = first.value;
        message = detail is List && detail.isNotEmpty
            ? '$message (${first.key}: ${detail.first})'
            : message;
      }
    } catch (_) {
      // Non-JSON error body: report the status as-is.
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

  Future<List<ClinicAppointment>> list({
    required String access,
    String? status,
    bool? upcoming,
  }) async {
    final query = <String, String>{
      if (status != null && status.isNotEmpty) 'status': status,
      if (upcoming != null) 'upcoming': upcoming ? '1' : '0',
    };
    final res = await _client
        .get(_uri(['appointments'], query), headers: _headers(access))
        .timeout(_timeout);
    return _list(res)
        .map((e) => ClinicAppointment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ClinicAppointment> get({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['appointments', uid]), headers: _headers(access))
        .timeout(_timeout);
    return ClinicAppointment.fromJson(_body(res));
  }

  /// Book a visit. `facilityUid` must be a verified clinic: the server rejects
  /// anything else, so the picker only ever offers facilities it returned.
  Future<ClinicAppointment> book({
    required String access,
    required String facilityUid,
    required String scheduledAt,
    String appointmentType = 'FOLLOW_UP',
    String? doctorUid,
    String reason = '',
    int durationMinutes = 30,
    bool reminderEnabled = true,
    List<int> reminderDaysBefore = const [1],
    List<String> reminderTimes = const ['07:00'],
    List<String> reminderChannels = const ['in_app'],
  }) async {
    final res = await _client
        .post(
          _uri(['appointments']),
          headers: _writeHeaders(access),
          body: jsonEncode({
            'facility_uid': facilityUid,
            'scheduled_at': scheduledAt,
            'appointment_type': appointmentType,
            if (doctorUid != null && doctorUid.isNotEmpty)
              'doctor_uid': doctorUid,
            if (reason.isNotEmpty) 'reason': reason,
            'duration_minutes': durationMinutes,
            'reminder_enabled': reminderEnabled,
            'reminder_days_before': reminderDaysBefore,
            'reminder_times': reminderTimes,
            'reminder_channels': reminderChannels,
          }),
        )
        .timeout(_timeout);
    return ClinicAppointment.fromJson(_body(res));
  }

  /// Reschedule. The server keeps the previous row as history rather than
  /// editing it in place.
  Future<ClinicAppointment> reschedule({
    required String access,
    required String uid,
    required String scheduledAt,
    String? reason,
  }) async {
    final res = await _client
        .patch(
          _uri(['appointments', uid]),
          headers: _writeHeaders(access),
          body: jsonEncode({
            'scheduled_at': scheduledAt,
            if (reason != null && reason.isNotEmpty) 'reason': reason,
          }),
        )
        .timeout(_timeout);
    return ClinicAppointment.fromJson(_body(res));
  }

  /// Verified clinics for the booking picker (`GET /facilities/`).
  ///
  /// The server's `validate_facility_uid` refuses anything unverified, so the
  /// app must offer a real verified uid rather than a typed name. An explicit
  /// [client] lets a widget test serve the directory without a second repository.
  Future<List<BookableFacility>> listFacilities({
    required String access,
    http.Client? client,
  }) async {
    final res = await (client ?? _client)
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/facilities/'),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return _list(res)
        .map((e) => BookableFacility.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Audited status transition. A cancellation always carries a reason: the
  /// server records it on the appointment.
  Future<ClinicAppointment> setStatus({
    required String access,
    required String uid,
    required String status,
    String reason = '',
  }) async {
    final res = await _client
        .post(
          _uri(['appointments', uid, 'status']),
          headers: _writeHeaders(access),
          body: jsonEncode({
            'status': status,
            if (reason.isNotEmpty) 'reason': reason,
          }),
        )
        .timeout(_timeout);
    return ClinicAppointment.fromJson(_body(res));
  }
}

/// A verified clinic, for the booking picker. Only `is_verified` rows are
/// offered, matching the server's `validate_facility_uid`.
class BookableFacility {
  const BookableFacility({
    required this.uid,
    required this.name,
    this.city = '',
    this.region = '',
    this.facilityType = '',
  });

  factory BookableFacility.fromJson(Map<String, dynamic> json) =>
      BookableFacility(
        uid: (json['uid'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        city: (json['city'] as String?) ?? '',
        region: (json['region'] as String?) ?? '',
        facilityType: (json['facility_type'] as String?) ?? '',
      );

  final String uid;
  final String name;
  final String city;
  final String region;
  final String facilityType;

  String get subtitle {
    final place = [city, region].where((p) => p.isNotEmpty).join(', ');
    return place.isEmpty ? name : '$name · $place';
  }
}