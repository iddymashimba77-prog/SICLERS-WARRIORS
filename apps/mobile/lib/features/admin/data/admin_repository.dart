/// ADMIN-3 data layer: typed client for the backend admin API.
///
/// Mirrors the approved admin endpoint matrix (Stage 4.22-4.16) exactly:
/// envelope unwrapping, pagination (`results`), error carving and Bearer auth
/// follow the same conventions as the feature repositories. Every call is
/// authorised server-side by the permission codes advertised in `/me`; this
/// client never asserts authorization itself.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';
import 'admin_models.dart';

class AdminRepository {
  AdminRepository({required this.tokenStore, http.Client? client})
      : _client = client ?? http.Client();

  final TokenStore tokenStore;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  Uri _uri(List<String> segments) =>
      Uri.parse('${AppConfig.apiBaseUrl}/${segments.join('/')}/');

  Uri _rawUri(List<String> segments) =>
      Uri.parse('${AppConfig.apiBaseUrl}/${segments.join('/')}');

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

  Map<String, dynamic> _responseBody(http.Response res) {
    if (res.statusCode == 401) {
      throw const AuthException('Session expired. Please sign in again.',
          code: 'TOKEN_EXPIRED', statusCode: 401);
    }
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return (map['data'] as Map<String, dynamic>?) ?? map;
  }

  List<dynamic> _listPayload(http.Response res) {
    final payload = _responseBody(res);
    final results = payload['results'];
    if (results is List) return results;
    return const [];
  }

  List<T> _map<T>(http.Response res, T Function(Map<String, dynamic>) from) =>
      [
        for (final row in _listPayload(res))
          if (row is Map<String, dynamic>) from(row),
      ];

  // ------------------------------------------------------------- users

  Future<List<AdminUser>> listUsers({
    required String access,
    String? status,
    String? query,
  }) async {
    final uri = _uri(['admin', 'users']).replace(
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        if (query != null && query.isNotEmpty) 'q': query,
      },
    );
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _map(res, AdminUser.fromJson);
  }

  Future<void> setUserStatus({
    required String access,
    required String uid,
    required bool activate,
    required String reason,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'users', uid, activate ? 'activate' : 'deactivate']),
          headers: _headers(access),
          body: jsonEncode({'reason': reason}),
        )
        .timeout(_timeout);
    _responseBody(res);
  }

  Future<List<String>> getUserRoles({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['admin', 'users', uid, 'roles']),
            headers: _headers(access))
        .timeout(_timeout);
    final payload = _responseBody(res);
    return [...?(payload['roles'] as List?)?.cast<String>()];
  }

  Future<AdminUser> changeUserRole({
    required String access,
    required String uid,
    required String roleCode,
    required bool grant,
    required String reason,
  }) async {
    final streamed = await _client
        .send(http.Request(
          grant ? 'POST' : 'DELETE',
          _uri(['admin', 'users', uid, 'roles']),
        )
          ..headers.addAll(_headers(access))
          ..body = jsonEncode({'role_code': roleCode, 'reason': reason}))
        .timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
    return AdminUser.fromJson(_responseBody(res));
  }

  // ------------------------------------------------------- security events

  Future<List<SecurityEvent>> listSecurityEvents({
    required String access,
    String? eventType,
    String? status,
  }) async {
    final uri = _uri(['admin', 'security-events']).replace(
      queryParameters: {
        if (eventType != null && eventType.isNotEmpty) 'event_type': eventType,
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _map(res, SecurityEvent.fromJson);
  }

  // -------------------------------------------------------------- doctors

  Future<List<AdminDoctor>> listDoctorQueue({required String access}) async {
    final res = await _client
        .get(_uri(['admin', 'doctors', 'verification-queue']),
            headers: _headers(access))
        .timeout(_timeout);
    return _map(res, AdminDoctor.fromJson);
  }

  /// GET /api/admin/verification-documents/{id}/ — the audited bytes of one
  /// submitted document, for a reviewer holding doctors.verify/facilities.verify.
  ///
  /// Returned as raw bytes (never a public URL) so the caller can preview an
  /// image in-app or hand a PDF to the device's own viewer.
  Future<AdminDocumentBytes> fetchVerificationDocument({
    required String access,
    required int id,
  }) async {
    final res = await _client
        .get(_uri(['admin', 'verification-documents', '$id']), headers: {
          'Accept': '*/*',
          'Authorization': 'Bearer $access',
        })
        .timeout(_timeout);
    if (res.statusCode == 401) {
      throw const AuthException('Session expired. Please sign in again.',
          code: 'TOKEN_EXPIRED', statusCode: 401);
    }
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    return AdminDocumentBytes(
      bytes: res.bodyBytes,
      contentType: res.headers['content-type'] ?? 'application/octet-stream',
    );
  }

  Future<void> decideDoctor({
    required String access,
    required String uid,
    required bool approve,
    required String reason,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'doctors', uid, 'verify']),
          headers: _headers(access),
          body: jsonEncode({'approve': approve, 'reason': reason}),
        )
        .timeout(_timeout);
    _responseBody(res);
  }

  /// The append-only verification trail for one doctor (`FR-DOC-007`).
  ///
  /// The review queue reads the same route the applicant reads, so an officer
  /// sees earlier refusals before deciding the next case.
  Future<List<AdminDoctorVerificationDecision>> listDoctorVerificationHistory({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['doctors', uid, 'verification-history']),
            headers: _headers(access))
        .timeout(_timeout);
    final rows = _responseBody(res)['decisions'];
    return [
      for (final row in (rows is List ? rows : const <dynamic>[]))
        AdminDoctorVerificationDecision.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<void> suspendDoctor({
    required String access,
    required String uid,
    required String reason,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'doctors', uid, 'suspend']),
          headers: _headers(access),
          body: jsonEncode({'reason': reason}),
        )
        .timeout(_timeout);
    _responseBody(res);
  }

  // ---------------------------------------------------------- organizations

  Future<List<AdminFacility>> listFacilities({
    required String access,
    String? status,
    String? query,
    String? facilityType,
  }) async {
    final uri = _uri(['admin', 'facilities']).replace(
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        if (query != null && query.isNotEmpty) 'q': query,
        if (facilityType != null && facilityType.isNotEmpty)
          'facility_type': facilityType,
      },
    );
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _map(res, AdminFacility.fromJson);
  }

  /// POST /api/admin/facilities/{uid}/verify — registered WITHOUT a trailing
  /// slash on the backend, so the raw URI builder is used here.
  Future<void> verifyFacility({
    required String access,
    required String uid,
    required bool approve,
    required String reason,
  }) async {
    final res = await _client
        .post(
          _rawUri(['admin', 'facilities', uid, 'verify']),
          headers: _headers(access),
          body: jsonEncode({'approve': approve, 'reason': reason}),
        )
        .timeout(_timeout);
    _responseBody(res);
  }

  // ---------------------------------------------------------- blood network

  Future<List<AdminBloodRequest>> listBloodQueue({required String access}) async {
    final res = await _client
        .get(_uri(['blood', 'requests', 'verification-queue']),
            headers: _headers(access))
        .timeout(_timeout);
    return _map(res, AdminBloodRequest.fromJson);
  }

  Future<void> decideBloodRequest({
    required String access,
    required String uid,
    required bool approve,
    String? reason,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'blood', 'requests', uid, approve ? 'verify' : 'reject']),
          headers: _headers(access),
          body: jsonEncode({
            if (reason != null && reason.isNotEmpty) 'reason': reason,
          }),
        )
        .timeout(_timeout);
    _responseBody(res);
  }

  // ------------------------------------------------------------- campaigns

  Future<List<AdminCampaign>> listCampaigns({
    required String access,
    String? status,
  }) async {
    final uri = _uri(['admin', 'campaigns']).replace(
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _map(res, AdminCampaign.fromJson);
  }

  Future<List<AdminCampaign>> listCampaignQueue({required String access}) async {
    final res = await _client
        .get(_uri(['admin', 'campaigns', 'verification-queue']),
            headers: _headers(access))
        .timeout(_timeout);
    return _map(res, AdminCampaign.fromJson);
  }

  Future<void> decideCampaign({
    required String access,
    required String uid,
    required bool approve,
    required String reason,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'campaigns', uid, 'verify']),
          headers: _headers(access),
          body: jsonEncode({'approve': approve, 'reason': reason}),
        )
        .timeout(_timeout);
    _responseBody(res);
  }

  Future<void> pauseCampaign({
    required String access,
    required String uid,
    String? reason,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'campaigns', uid, 'pause']),
          headers: _headers(access),
          body: jsonEncode({'reason': reason ?? ''}),
        )
        .timeout(_timeout);
    _responseBody(res);
  }

  Future<void> closeCampaign({
    required String access,
    required String uid,
    String? reason,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'campaigns', uid, 'close']),
          headers: _headers(access),
          body: jsonEncode({'reason': reason ?? ''}),
        )
        .timeout(_timeout);
    _responseBody(res);
  }

  // ------------------------------------------------------- roles management

  Future<List<AdminRole>> listRoles({required String access}) async {
    final res = await _client
        .get(_uri(['admin', 'roles']), headers: _headers(access))
        .timeout(_timeout);
    return _map(res, AdminRole.fromJson);
  }

  Future<List<String>> listRolePermissions({
    required String access,
    required String roleCode,
  }) async {
    final res = await _client
        .get(_uri(['admin', 'roles', roleCode, 'permissions']),
            headers: _headers(access))
        .timeout(_timeout);
    final payload = _responseBody(res);
    return [...?(payload['permission_codes'] as List?)?.cast<String>()];
  }

  Future<List<String>> setRolePermission({
    required String access,
    required String roleCode,
    required String permissionCode,
    required bool grant,
    required String reason,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'roles', roleCode, 'permissions']),
          headers: _headers(access),
          body: jsonEncode({
            'permission_code': permissionCode,
            'grant': grant,
            'reason': reason,
          }),
        )
        .timeout(_timeout);
    final payload = _responseBody(res);
    return [...?(payload['permission_codes'] as List?)?.cast<String>()];
  }

  // --------------------------------------------------------- content review

  Future<List<AdminContent>> listContent({
    required String access,
    String? status,
  }) async {
    final uri = _uri(['admin', 'education', 'content']).replace(
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _map(res, AdminContent.fromJson);
  }

  Future<void> reviewContent({
    required String access,
    required String uid,
    required String decision, // approve | reject
    String? reason,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'education', 'content', uid, 'review']),
          headers: _headers(access),
          body: jsonEncode({
            'decision': decision,
            if (reason != null && reason.isNotEmpty) 'reason': reason,
          }),
        )
        .timeout(_timeout);
    _responseBody(res);
  }

  // ------------------------------------------------------------- moderation

  Future<List<AdminReport>> listReports({required String access}) async {
    final res = await _client
        .get(_uri(['admin', 'community', 'reports']),
            headers: _headers(access))
        .timeout(_timeout);
    return _map(res, AdminReport.fromJson);
  }

  Future<void> resolveReport({
    required String access,
    required int id,
    required String status, // RESOLVED | DISMISSED
    String action = 'NONE', // NONE | HIDE | REMOVE
    String? reviewNotes,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'community', 'reports', '$id', 'resolve']),
          headers: _headers(access),
          body: jsonEncode({
            'status': status,
            'action': action,
            if (reviewNotes != null && reviewNotes.isNotEmpty)
              'review_notes': reviewNotes,
          }),
        )
        .timeout(_timeout);
    _responseBody(res);
  }

  // --------------------------------------------------------------- finance

  Future<List<AdminDonation>> listDonations({required String access}) async {
    final res = await _client
        .get(_uri(['admin', 'donations']), headers: _headers(access))
        .timeout(_timeout);
    return _map(res, AdminDonation.fromJson);
  }

  Future<AdminDonation> refundDonation({
    required String access,
    required String uid,
    required double amount,
    required String reason,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'donations', uid, 'refund']),
          headers: _headers(access),
          body: jsonEncode({'reason': reason, 'amount': amount}),
        )
        .timeout(_timeout);
    return AdminDonation.fromJson(_responseBody(res));
  }

  Future<AdminFinancialSummary> financialSummary({required String access}) async {
    final res = await _client
        .get(_uri(['admin', 'financial', 'summary']),
            headers: _headers(access))
        .timeout(_timeout);
    return AdminFinancialSummary.fromJson(_responseBody(res));
  }

  // -------------------------------------------------------------- broadcast

  Future<AdminBroadcastResult> broadcast({
    required String access,
    required String audience, // ALL | ROLE | USERS
    required String title,
    required String body,
    String? roleCode,
    List<String>? userUids,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'notifications', 'broadcast']),
          headers: _headers(access),
          body: jsonEncode({
            'audience': audience,
            'title': title,
            'body': body,
            'role_code': roleCode ?? '',
            'user_uid': userUids ?? [],
          }),
        )
        .timeout(_timeout);
    return AdminBroadcastResult.fromJson(_responseBody(res));
  }

  // -------------------------------------------------------------- audit logs

  Future<List<AdminAuditLog>> listAuditLogs({
    required String access,
    String? actionCode,
    String? resourceType,
    String? result,
    String? actor,
    String? dateFrom,
    String? dateTo,
  }) async {
    final uri = _uri(['admin', 'audit-logs']).replace(
      queryParameters: {
        if (actionCode != null && actionCode.isNotEmpty) 'action_code': actionCode,
        if (resourceType != null && resourceType.isNotEmpty)
          'resource_type': resourceType,
        if (result != null && result.isNotEmpty) 'result': result,
        if (actor != null && actor.isNotEmpty) 'actor': actor,
        if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      },
    );
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _map(res, AdminAuditLog.fromJson);
  }

  // --------------------------------------------------- dashboard + analytics

  Future<AdminDashboard> dashboard({required String access}) async {
    final res = await _client
        .get(_uri(['admin', 'dashboard']), headers: _headers(access))
        .timeout(_timeout);
    return AdminDashboard.fromJson(_responseBody(res));
  }

  Future<AnalyticsResult> analytics({
    required String access,
    required String metric,
    required String granularity,
    String? dateFrom,
    String? dateTo,
  }) async {
    final uri = _uri(['admin', 'analytics']).replace(
      queryParameters: {
        'metric': metric,
        'granularity': granularity,
        if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      },
    );
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return AnalyticsResult.fromJson(_responseBody(res));
  }

  Future<AiMonitoring> aiMonitoring({
    required String access,
    int days = 30,
  }) async {
    final uri = _uri(['admin', 'ai', 'monitoring'])
        .replace(queryParameters: {'days': '$days'});
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return AiMonitoring.fromJson(_responseBody(res));
  }

  // ------------------------------------------------------- content CMS (news)

  Future<List<AdminNewsArticle>> listNewsArticles({
    required String access,
    String? status,
    String? category,
    String? query,
  }) async {
    final uri = _uri(['admin', 'content', 'news']).replace(
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        if (category != null && category.isNotEmpty) 'category': category,
        if (query != null && query.isNotEmpty) 'q': query,
      },
    );
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _map(res, AdminNewsArticle.fromJson);
  }

  Future<AdminNewsArticle> createNewsArticle({
    required String access,
    required String title,
    required String category,
    required String body,
    String excerpt = '',
    String coverUrl = '',
    String coverAlt = '',
    List<String> tags = const [],
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'content', 'news']),
          headers: _headers(access),
          body: jsonEncode({
            'title': title,
            'category': category,
            'body': body,
            if (excerpt.isNotEmpty) 'excerpt': excerpt,
            if (coverUrl.isNotEmpty) 'cover_url': coverUrl,
            if (coverAlt.isNotEmpty) 'cover_alt': coverAlt,
            if (tags.isNotEmpty) 'tags': tags,
          }),
        )
        .timeout(_timeout);
    return AdminNewsArticle.fromJson(_responseBody(res));
  }

  Future<AdminNewsArticle> updateNewsArticle({
    required String access,
    required String uid,
    String? title,
    String? category,
    String? excerpt,
    String? body,
    String? coverUrl,
    String? coverAlt,
    List<String>? tags,
  }) async {
    final res = await _client
        .patch(
          _uri(['admin', 'content', 'news', uid]),
          headers: _headers(access),
          body: jsonEncode({
            if (title != null) 'title': title,
            if (category != null) 'category': category,
            if (excerpt != null) 'excerpt': excerpt,
            if (body != null) 'body': body,
            if (coverUrl != null) 'cover_url': coverUrl,
            if (coverAlt != null) 'cover_alt': coverAlt,
            if (tags != null) 'tags': tags,
          }),
        )
        .timeout(_timeout);
    return AdminNewsArticle.fromJson(_responseBody(res));
  }

  Future<void> setNewsStatus({
    required String access,
    required String uid,
    required String action, // publish | unpublish | archive
  }) async {
    final res = await _client
        .post(_uri(['admin', 'content', 'news', uid, action]),
            headers: _headers(access))
        .timeout(_timeout);
    _responseBody(res);
  }

  Future<void> setNewsFeatured({
    required String access,
    required String uid,
    required bool featured,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'content', 'news', uid, 'feature']),
          headers: _headers(access),
          body: jsonEncode({'featured': featured}),
        )
        .timeout(_timeout);
    _responseBody(res);
  }

  /// POST /api/admin/content/news/{uid}/cover/ — real multipart image upload.
  /// The backend re-encodes/probes the bytes; only image/png, image/jpeg and
  /// image/webp content types are accepted (5 MB cap). The UI layer uses the
  /// cover-URL field for now; this client is the complete upload path.
  Future<void> uploadNewsCover({
    required String access,
    required String uid,
    required List<int> bytes,
    required String filename,
    required String contentType, // image/png | image/jpeg | image/webp
    String alt = '',
  }) async {
    final uri = _uri(['admin', 'content', 'news', uid, 'cover']);
    final media = MediaType.parse(contentType);
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $access',
      })
      ..fields['alt'] = alt
      ..files.add(http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: filename,
        contentType: media,
      ));
    final streamed = await _client.send(request).timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
    _responseBody(res);
  }

  Future<void> deleteNewsArticle({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .delete(_uri(['admin', 'content', 'news', uid]),
            headers: _headers(access))
        .timeout(_timeout);
    _responseBody(res);
  }

  // ---------------------------------------------- content CMS (ticker)

  Future<List<AdminTickerAnnouncement>> listTicker({
    required String access,
    bool? active,
  }) async {
    final uri = _uri(['admin', 'content', 'ticker']).replace(
      queryParameters: {
        if (active != null) 'active': active ? 'true' : 'false',
      },
    );
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _map(res, AdminTickerAnnouncement.fromJson);
  }

  Future<AdminTickerAnnouncement> createTicker({
    required String access,
    required String message,
    required String type, // INFO | URGENT | BLOOD | EVENT | DONATION | SUCCESS
    String linkUrl = '',
    bool isActive = false,
    int priority = 0,
    String? startAt,
    String? endAt,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'content', 'ticker']),
          headers: _headers(access),
          body: jsonEncode({
            'message': message,
            'announcement_type': type,
            if (linkUrl.isNotEmpty) 'link_url': linkUrl,
            'is_active': isActive,
            'priority': priority,
            if (startAt != null && startAt.isNotEmpty) 'start_at': startAt,
            if (endAt != null && endAt.isNotEmpty) 'end_at': endAt,
          }),
        )
        .timeout(_timeout);
    return AdminTickerAnnouncement.fromJson(_responseBody(res));
  }

  Future<AdminTickerAnnouncement> updateTicker({
    required String access,
    required String uid,
    String? message,
    String? type,
    String? linkUrl,
    bool? isActive,
    int? priority,
    String? startAt,
    String? endAt,
  }) async {
    final res = await _client
        .patch(
          _uri(['admin', 'content', 'ticker', uid]),
          headers: _headers(access),
          body: jsonEncode({
            if (message != null) 'message': message,
            if (type != null) 'announcement_type': type,
            if (linkUrl != null) 'link_url': linkUrl,
            if (isActive != null) 'is_active': isActive,
            if (priority != null) 'priority': priority,
            if (startAt != null) 'start_at': startAt,
            if (endAt != null) 'end_at': endAt,
          }),
        )
        .timeout(_timeout);
    return AdminTickerAnnouncement.fromJson(_responseBody(res));
  }

  Future<void> setTickerActive({
    required String access,
    required String uid,
    required bool active,
  }) async {
    final res = await _client
        .post(
          _uri(['admin', 'content', 'ticker', uid, active ? 'activate' : 'deactivate']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    _responseBody(res);
  }

  Future<void> deleteTicker({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .delete(_uri(['admin', 'content', 'ticker', uid]),
            headers: _headers(access))
        .timeout(_timeout);
    _responseBody(res);
  }
}