import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/domain/auth_types.dart';

class HydrationEntry {
  const HydrationEntry({
    required this.uid,
    required this.amountMl,
    required this.recordedAt,
  });

  factory HydrationEntry.fromJson(Map<String, dynamic> json) => HydrationEntry(
        uid: json['uid'] as String? ?? '',
        amountMl: (json['amount_ml'] as num?)?.toInt() ?? 0,
        recordedAt: DateTime.tryParse(json['recorded_at'] as String? ?? ''),
      );

  final String uid;
  final int amountMl;
  final DateTime? recordedAt;
}

class HydrationDay {
  const HydrationDay({
    required this.date,
    required this.goalMl,
    required this.consumedMl,
    required this.remainingMl,
    required this.progressPct,
    required this.entries,
  });

  factory HydrationDay.fromJson(Map<String, dynamic> json) => HydrationDay(
        date: json['date'] as String? ?? '',
        goalMl: (json['goal_ml'] as num?)?.toInt(),
        consumedMl: (json['consumed_ml'] as num?)?.toInt() ?? 0,
        remainingMl: (json['remaining_ml'] as num?)?.toInt(),
        progressPct: (json['progress_pct'] as num?)?.toInt(),
        entries: ((json['entries'] as List?) ?? const [])
            .map((e) => HydrationEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String date;
  final int? goalMl;
  final int consumedMl;
  final int? remainingMl;
  final int? progressPct;
  final List<HydrationEntry> entries;
}

/// Patient-owned hydration API client (`/api/patients/me/hydration/`).
///
/// The backend enforces PATIENT + hydration.* permissions. There is no client
/// default goal: the UI must not imply a universal fluid target.
class HydrationRepository {
  HydrationRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  Uri _uri(List<String> segments, {Map<String, String>? query}) => Uri.parse(
        '${AppConfig.apiBaseUrl}/${segments.join('/')}/',
      ).replace(queryParameters: query);

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
    final data = map['data'];
    if (data is Map<String, dynamic>) return data;
    throw const AuthException('Unexpected response from the server.',
        code: 'API_ERROR');
  }

  Future<HydrationDay> fetchDay({
    required String access,
    DateTime? date,
  }) async {
    final res = await _client
        .get(
          _uri(
            ['patients', 'me', 'hydration'],
            query: {
              if (date != null)
                'date': '${date.year.toString().padLeft(4, '0')}-'
                    '${date.month.toString().padLeft(2, '0')}-'
                    '${date.day.toString().padLeft(2, '0')}',
            },
          ),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return HydrationDay.fromJson(_body(res));
  }

  Future<HydrationEntry> addIntake({
    required String access,
    required int amountMl,
    DateTime? recordedAt,
  }) async {
    final res = await _client
        .post(
          _uri(['patients', 'me', 'hydration']),
          headers: _headers(access),
          body: jsonEncode({
            'amount_ml': amountMl,
            if (recordedAt != null) 'recorded_at': recordedAt.toUtc().toIso8601String(),
          }),
        )
        .timeout(_timeout);
    return HydrationEntry.fromJson(_body(res));
  }

  Future<int?> setGoal({required String access, required int? goalMl}) async {
    final res = await _client
        .patch(
          _uri(['patients', 'me', 'hydration', 'goal']),
          headers: _headers(access),
          body: jsonEncode({'hydration_goal_ml': goalMl}),
        )
        .timeout(_timeout);
    return (_body(res)['hydration_goal_ml'] as num?)?.toInt();
  }
}
