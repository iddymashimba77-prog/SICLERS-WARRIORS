/// Approved Stage 4.13 API client for `/api/notifications/*`.
///
/// Mirrors the approved database-design row `notifications` (§19) and the
/// endpoint-matrix notification surface. Ownership is recipient-only and
/// enforced server-side (IDOR-safe: foreign ids yield 404).
///
/// Emergency notifications are never suppressible (FR-EMG / BR-009); the
/// preferences surface only exposes the mutable categories the backend allows.
///
/// Push delivery is a backend extension point (Stage 4.14+): the device/token
/// client here registers, lists and deactivates the current device so FCM can
/// be wired later without client changes. Tokens are write-only on the server
/// and are never echoed back to this client.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

/// Notification categories (mirror `Notification.TYPE`).
const List<String> notificationCategories = [
  'MEDICATION_REMINDER',
  'APPOINTMENT',
  'BLOOD',
  'EMERGENCY',
  'PAYMENT',
  'COMMUNITY',
  'CONSENT',
  'SYSTEM',
];

/// Push device platform tokens (mirror `PushDevice.PLATFORM`).
const List<String> pushDevicePlatforms = ['ANDROID', 'IOS', 'WEB', 'OTHER'];

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.channel,
    required this.title,
    required this.body,
    required this.status,
    required this.priority,
    required this.data,
    this.readAt,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: (json['id'] as num?)?.toInt() ?? 0,
        type: (json['type'] as String?) ?? 'SYSTEM',
        channel: (json['channel'] as String?) ?? 'IN_APP',
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'PENDING',
        priority: (json['priority'] as String?) ?? 'NORMAL',
        data: (json['data'] is Map<String, dynamic>)
            ? json['data'] as Map<String, dynamic>
            : const <String, dynamic>{},
        readAt: json['read_at'] as String?,
        createdAt: json['created_at'] as String?,
      );

  final int id;
  final String type;
  final String channel;
  final String title;
  final String body;
  final String status;
  final String priority;
  final Map<String, dynamic> data;
  final String? readAt;
  final String? createdAt;

  bool get isUnread => status != 'READ';

  bool get isEmergency => type == 'EMERGENCY';

  bool get isCritical => priority == 'CRITICAL' || isEmergency;

  bool get isHighPriority => priority == 'HIGH';

  /// Approved in-app deep-link target (allowlist enforced on navigation).
  String? get route => data['route'] is String ? data['route'] as String : null;
}

/// A push delivery device registered against the caller's account.
class PushDevice {
  const PushDevice({
    required this.id,
    required this.platform,
    required this.deviceId,
    required this.isActive,
    this.lastSeenAt,
  });

  factory PushDevice.fromJson(Map<String, dynamic> json) => PushDevice(
        id: (json['id'] as num?)?.toInt() ?? 0,
        platform: (json['platform'] as String?) ?? 'OTHER',
        deviceId: (json['device_id'] as String?) ?? '',
        isActive: json['is_active'] == true,
        lastSeenAt: json['last_seen_at'] as String?,
      );

  final int id;
  final String platform;
  final String deviceId;
  final bool isActive;
  final String? lastSeenAt;
}

/// Client for the approved notification endpoints.
class NotificationsRepository {
  NotificationsRepository({required this.tokenStore, http.Client? client})
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

  Future<List<AppNotification>> list({required String access}) async {
    final res = await _client
        .get(_uri(['notifications']), headers: _headers(access))
        .timeout(_timeout);
    final payload = _body(res);
    final results = payload['results'];
    if (results is List) {
      return results
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return const [];
  }

  Future<AppNotification> markRead({
    required String access,
    required int id,
  }) async {
    final res = await _client
        .post(_uri(['notifications', '$id', 'read']), headers: _headers(access))
        .timeout(_timeout);
    return AppNotification.fromJson(_body(res));
  }

  /// Unread (non-suppressed) count used for the inbox badge (FR-NOT-005).
  Future<int> unreadCount({required String access}) async {
    final res = await _client
        .get(_uri(['notifications', 'unread-count']), headers: _headers(access))
        .timeout(_timeout);
    return (_body(res)['unread'] as num?)?.toInt() ?? 0;
  }

  Future<int> readAll({required String access}) async {
    final res = await _client
        .post(_uri(['notifications', 'read-all']), headers: _headers(access))
        .timeout(_timeout);
    return (_body(res)['updated'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, bool>> getPreferences({
    required String access,
  }) async {
    final res = await _client
        .get(_uri(['notifications', 'preferences']), headers: _headers(access))
        .timeout(_timeout);
    final prefs = _body(res)['preferences'];
    if (prefs is Map) {
      return prefs.map((k, v) => MapEntry('$k', v == true));
    }
    return const {};
  }

  Future<void> updatePreference({
    required String access,
    required String category,
    required bool enabled,
  }) async {
    final res = await _client
        .patch(
          _uri(['notifications', 'preferences']),
          headers: _headers(access),
          body: jsonEncode({'category': category, 'enabled': enabled}),
        )
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
  }

  /// Registers (or rotates) the device push token (Stage 4.13 §device mgmt).
  ///
  /// The token is write-only: it is only ever sent in the request body and the
  /// response deliberately never contains it.
  Future<PushDevice> registerDevice({
    required String access,
    required String pushToken,
    required String platform,
    required String deviceId,
  }) async {
    final res = await _client
        .post(
          _uri(['notifications', 'devices']),
          headers: _headers(access),
          body: jsonEncode({
            'push_token': pushToken,
            'platform': platform,
            'device_id': deviceId,
          }),
        )
        .timeout(_timeout);
    return PushDevice.fromJson(_body(res));
  }

  /// Lists the caller's registered devices.
  Future<List<PushDevice>> listDevices({required String access}) async {
    final res = await _client
        .get(_uri(['notifications', 'devices']), headers: _headers(access))
        .timeout(_timeout);
    final payload = _bodyList(res);
    return [
      for (final e in payload) PushDevice.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// Deactivates (soft-deletes) one of the caller's devices by id.
  Future<void> deactivateDevice({
    required String access,
    required int id,
  }) async {
    final res = await _client
        .delete(
          _uri(['notifications', 'devices', '$id']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
  }

  /// Parses `{"data": [...]}` envelopes for list endpoints.
  List<dynamic> _bodyList(http.Response res) {
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final payload = map['data'];
    return payload is List ? payload : const [];
  }
}
