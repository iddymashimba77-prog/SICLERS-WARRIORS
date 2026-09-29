/// Approved Stage 4.8 API client for `/api/emergency/*`.
///
/// Mirrors the approved database-design rows (`emergency_requests`,
/// `emergency_responders`, `emergency_access_grants`) and endpoint matrix §13.
///
/// Deny by default: a caller only sees requests they own or actively respond
/// to. Creation is rate-limited (3/hour/user, FR-EMG-001) and idempotent
/// (approved §30 duplicate key → 409).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

const List<String> emergencyTypes = [
  'MEDICAL',
  'PAIN_CRISIS',
  'BLOOD',
  'FALL',
  'OTHER',
];

const List<String> emergencySeverities = ['NORMAL', 'URGENT', 'CRITICAL'];

/// One responder entry on a request (EMG-004 timeline). Carries no PII: the
/// backend deliberately omits responder contact details from the owner view.
class EmergencyResponder {
  const EmergencyResponder({
    required this.role,
    required this.status,
    this.acknowledgedAt,
    this.arrivedAt,
    this.updatedAt,
  });

  factory EmergencyResponder.fromJson(Map<String, dynamic> json) =>
      EmergencyResponder(
        role: (json['responder_role'] as String?) ?? 'OTHER',
        status: (json['status'] as String?) ?? '',
        acknowledgedAt: json['acknowledged_at'] as String?,
        arrivedAt: json['arrived_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  final String role;
  final String status;
  final String? acknowledgedAt;
  final String? arrivedAt;
  final String? updatedAt;
}

class EmergencyRequest {
  const EmergencyRequest({
    required this.uid,
    required this.severity,
    required this.type,
    required this.description,
    required this.location,
    required this.status,
    required this.rateLimitOk,
    required this.phoneVerified,
    this.escalatedAt,
    this.resolvedAt,
    this.createdAt,
    this.responders = const [],
  });

  factory EmergencyRequest.fromJson(Map<String, dynamic> json) =>
      EmergencyRequest(
        uid: (json['uid'] as String?) ?? '',
        severity: (json['severity'] as String?) ?? 'NORMAL',
        type: (json['type'] as String?) ?? 'OTHER',
        description: (json['description'] as String?) ?? '',
        location: json['location'],
        status: (json['status'] as String?) ?? '',
        rateLimitOk: (json['rate_limit_ok'] as bool?) ?? true,
        phoneVerified: (json['phone_verified'] as bool?) ?? false,
        escalatedAt: json['escalated_at'] as String?,
        resolvedAt: json['resolved_at'] as String?,
        createdAt: json['created_at'] as String?,
        responders: [
          for (final r in (json['responders'] as List<dynamic>? ?? const []))
            EmergencyResponder.fromJson(r as Map<String, dynamic>),
        ],
      );

  final String uid;
  final String severity;
  final String type;
  final String description;
  final dynamic location;
  final String status;
  final bool rateLimitOk;
  final bool phoneVerified;
  final String? escalatedAt;
  final String? resolvedAt;
  final String? createdAt;
  final List<EmergencyResponder> responders;

  bool get isActive => const [
        'CREATED',
        'VALIDATING',
        'ACTIVE',
        'RESPONDING',
        'ESCALATED',
      ].contains(status);

  bool get isResolved => status == 'RESOLVED';

  /// Human-readable location (free text or region/city) for tracking.
  String get locationLabel {
    final value = location;
    if (value is Map) {
      final text = value['text'] ?? value['address'];
      if (text is String && text.isNotEmpty) return text;
      final parts = [value['city'], value['region']]
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) return parts.join(', ');
    }
    return '';
  }
}

class EmergencyAccessGrant {
  const EmergencyAccessGrant({
    required this.uid,
    required this.scope,
    required this.status,
    this.expiresAt,
  });

  factory EmergencyAccessGrant.fromJson(Map<String, dynamic> json) =>
      EmergencyAccessGrant(
        uid: (json['uid'] as String?) ?? '',
        scope: (json['scope'] as Map<String, dynamic>?) ?? const {},
        status: (json['status'] as String?) ?? '',
        expiresAt: json['expires_at'] as String?,
      );

  final String uid;
  final Map<String, dynamic> scope;
  final String status;
  final String? expiresAt;

  bool get isActive => status == 'ACTIVE';
}

/// Client for the approved emergency endpoints.
class EmergencyRepository {
  EmergencyRepository({required this.tokenStore, http.Client? client})
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

  Future<List<EmergencyRequest>> listRequests({
    required String access,
  }) async {
    final res = await _client
        .get(_uri(['emergency', 'requests']), headers: _headers(access))
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => EmergencyRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EmergencyRequest> createRequest({
    required String access,
    required String type,
    String severity = 'NORMAL',
    String description = '',
    Map<String, dynamic>? location,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? 'emg-${DateTime.now().microsecondsSinceEpoch}';
    final res = await _client
        .post(
          _uri(['emergency', 'requests']),
          headers: {..._headers(access), 'Idempotency-Key': key},
          body: jsonEncode({
            'type': type,
            'severity': severity,
            'description': description,
            if (location != null && location.isNotEmpty) 'location': location,
            'idempotency_key': key,
          }),
        )
        .timeout(_timeout);
    return EmergencyRequest.fromJson(_body(res));
  }

  Future<EmergencyRequest> getRequest({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['emergency', 'requests', uid]), headers: _headers(access))
        .timeout(_timeout);
    return EmergencyRequest.fromJson(_body(res));
  }

  Future<EmergencyRequest> validate({
    required String access,
    required String uid,
  }) =>
      _action(access: access, uid: uid, action: 'validate');

  Future<EmergencyRequest> _action({
    required String access,
    required String uid,
    required String action,
    Map<String, dynamic> body = const {},
  }) async {
    final res = await _client
        .post(
          _uri(['emergency', 'requests', uid, action]),
          headers: _headers(access),
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    return EmergencyRequest.fromJson(_body(res));
  }

  Future<EmergencyRequest> respond({
    required String access,
    required String uid,
  }) =>
      _action(access: access, uid: uid, action: 'respond');

  Future<EmergencyRequest> escalate({
    required String access,
    required String uid,
  }) =>
      _action(access: access, uid: uid, action: 'escalate');

  Future<EmergencyRequest> resolve({
    required String access,
    required String uid,
  }) =>
      _action(access: access, uid: uid, action: 'resolve');

  Future<EmergencyRequest> cancel({
    required String access,
    required String uid,
  }) =>
      _action(access: access, uid: uid, action: 'cancel');

  Future<List<EmergencyAccessGrant>> listAccessGrants({
    required String access,
  }) async {
    final res = await _client
        .get(_uri(['emergency', 'access-grants']), headers: _headers(access))
        .timeout(_timeout);
    return _listPayload(res)
        .map((e) => EmergencyAccessGrant.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
