import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

/// Patient-facing clinical chart (FR-MEDREC-001/002/006).
///
/// Two rules shape this whole file:
///
///  * **A file has no link.** The server returns `download_path`, never a
///    resolvable URL, and the bytes come from an authorized call. This client
///    therefore hands the app a path plus a fetch closure and nothing that could
///    be pasted into a chat and read later by whoever holds it.
///  * **The server decides the read set.** `GET /medical-records/` is already
///    scoped to consents, relationship and role; this client never widens it and
///    never renders a row the API did not return.
class MedicalRecordFile {
  const MedicalRecordFile({
    required this.uid,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.downloadPath,
    this.uploadedAt,
  });

  factory MedicalRecordFile.fromJson(Map<String, dynamic> json) =>
      MedicalRecordFile(
        uid: (json['uid'] as String?) ?? '',
        fileName: (json['file_name'] as String?) ?? '',
        contentType: (json['content_type'] as String?) ?? '',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        downloadPath: (json['download_path'] as String?) ?? '',
        uploadedAt: json['uploaded_at'] as String?,
      );

  final String uid;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String downloadPath;
  final String? uploadedAt;

  /// A path-safe local name for this file.
  ///
  /// `file_name` comes from the server, so it is treated as untrusted: path
  /// separators and parent references are stripped before the name is joined
  /// onto a directory. Without this, a stored name like `../../secret` would
  /// write outside the download folder.
  String get safeLocalName {
    final base = fileName.split('/').last.split(r'\').last.trim();
    final cleaned = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
        ? 'record-file-$uid'
        : cleaned;
  }

  String get readableSize {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// One append-only chart entry. `details` is non-PHI by construction (field
/// names, counts, statuses, file names), which is why this projection is safe
/// to show next to the record it describes.
class MedicalRecordEvent {
  const MedicalRecordEvent({
    required this.uid,
    required this.eventType,
    required this.actorName,
    required this.occurredAt,
    this.fromStatus = '',
    this.toStatus = '',
    this.details = const {},
  });

  factory MedicalRecordEvent.fromJson(Map<String, dynamic> json) =>
      MedicalRecordEvent(
        uid: (json['uid'] as String?) ?? '',
        eventType: (json['event_type'] as String?) ?? '',
        actorName: (json['actor_name'] as String?) ?? '',
        occurredAt: (json['occurred_at'] as String?) ?? '',
        fromStatus: (json['from_status'] as String?) ?? '',
        toStatus: (json['to_status'] as String?) ?? '',
        details: (json['details'] as Map<String, dynamic>?) ?? const {},
      );

  final String uid;
  final String eventType;
  final String actorName;
  final String occurredAt;
  final String fromStatus;
  final String toStatus;
  final Map<String, dynamic> details;
}

class RecordCategory {
  const RecordCategory({
    required this.code,
    required this.name,
    this.description = '',
  });

  factory RecordCategory.fromJson(Map<String, dynamic> json) => RecordCategory(
        code: (json['code'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
      );

  final String code;
  final String name;
  final String description;
}

/// The chart list row. Clinical text is *not* here — the server keeps
/// `description` out of the list projection so a list screen cannot leak a chart
/// note it was not opened for.
class MedicalRecordSummary {
  const MedicalRecordSummary({
    required this.uid,
    required this.title,
    required this.categoryCode,
    required this.categoryName,
    required this.status,
    required this.isConsentVisible,
    required this.recordedAt,
    this.facilityName = '',
    this.recordedByName = '',
    this.fileCount = 0,
  });

  factory MedicalRecordSummary.fromJson(Map<String, dynamic> json) =>
      MedicalRecordSummary(
        uid: (json['uid'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        categoryCode: (json['category_code'] as String?) ?? '',
        categoryName: (json['category_name'] as String?) ?? '',
        status: (json['status'] as String?) ?? '',
        isConsentVisible: (json['is_consent_visible'] as bool?) ?? false,
        recordedAt: (json['recorded_at'] as String?) ?? '',
        facilityName: (json['facility_name'] as String?) ?? '',
        recordedByName: (json['recorded_by_name'] as String?) ?? '',
        fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
      );

  final String uid;
  final String title;
  final String categoryCode;
  final String categoryName;
  final String status;
  final bool isConsentVisible;
  final String recordedAt;
  final String facilityName;
  final String recordedByName;
  final int fileCount;

  bool get isDraft => status == 'DRAFT';
  bool get isActive => status == 'ACTIVE';
}

class MedicalRecordDetail {
  const MedicalRecordDetail({
    required this.uid,
    required this.title,
    required this.description,
    required this.categoryCode,
    required this.categoryName,
    required this.status,
    required this.isConsentVisible,
    required this.recordedAt,
    required this.canEdit,
    required this.canUpload,
    this.facilityName = '',
    this.recordedByName = '',
    this.patientUid = '',
    this.files = const [],
  });

  factory MedicalRecordDetail.fromJson(Map<String, dynamic> json) =>
      MedicalRecordDetail(
        uid: (json['uid'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        categoryCode: (json['category_code'] as String?) ?? '',
        categoryName: (json['category_name'] as String?) ?? '',
        status: (json['status'] as String?) ?? '',
        isConsentVisible: (json['is_consent_visible'] as bool?) ?? false,
        recordedAt: (json['recorded_at'] as String?) ?? '',
        canEdit: (json['can_edit'] as bool?) ?? false,
        canUpload: (json['can_upload'] as bool?) ?? false,
        facilityName: (json['facility_name'] as String?) ?? '',
        recordedByName: (json['recorded_by_name'] as String?) ?? '',
        patientUid: (json['patient_uid'] as String?) ?? '',
        files: [
          for (final file in (json['files'] as List<dynamic>? ?? const []))
            MedicalRecordFile.fromJson(file as Map<String, dynamic>),
        ],
      );

  final String uid;
  final String title;
  final String description;
  final String categoryCode;
  final String categoryName;
  final String status;
  final bool isConsentVisible;
  final String recordedAt;
  final bool canEdit;
  final bool canUpload;
  final String facilityName;
  final String recordedByName;
  final String patientUid;
  final List<MedicalRecordFile> files;

  bool get isDraft => status == 'DRAFT';
  bool get isActive => status == 'ACTIVE';

  MedicalRecordSummary get asSummary => MedicalRecordSummary(
        uid: uid,
        title: title,
        categoryCode: categoryCode,
        categoryName: categoryName,
        status: status,
        isConsentVisible: isConsentVisible,
        recordedAt: recordedAt,
        facilityName: facilityName,
        recordedByName: recordedByName,
        fileCount: files.length,
      );
}

class MedicalRecordsRepository {
  MedicalRecordsRepository({required this.tokenStore, http.Client? client})
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

  /// The patient's own chart. `status` and `category` are the server's filters;
  /// an unknown value comes back as a 400 rather than an empty page, so the UI
  /// surfaces the message instead of pretending the chart is empty.
  Future<List<MedicalRecordSummary>> listRecords({
    required String access,
    String? status,
    String? category,
  }) async {
    final query = <String, String>{
      if (status != null && status.isNotEmpty) 'status': status,
      if (category != null && category.isNotEmpty) 'category': category,
    };
    final res = await _client
        .get(_uri(['medical-records'], query), headers: _headers(access))
        .timeout(_timeout);
    return _list(res)
        .map((e) => MedicalRecordSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MedicalRecordDetail> getRecord({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['medical-records', uid]), headers: _headers(access))
        .timeout(_timeout);
    return MedicalRecordDetail.fromJson(_body(res));
  }

  /// Append-only history for one record (FR-MEDREC-006).
  Future<List<MedicalRecordEvent>> listHistory({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(
          _uri(['medical-records', uid, 'history']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return _list(res)
        .map((e) => MedicalRecordEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Chart-wide history across every record the caller may read.
  Future<List<MedicalRecordEvent>> listChartHistory({
    required String access,
  }) async {
    final res = await _client
        .get(
          _uri(['medical-records', 'history']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return _list(res)
        .map((e) => MedicalRecordEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<RecordCategory>> listCategories({required String access}) async {
    final res = await _client
        .get(_uri(['record-categories']), headers: _headers(access))
        .timeout(_timeout);
    return _list(res)
        .map((e) => RecordCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Move a record between DRAFT / ACTIVE / REVOKED / EXPIRED.
  Future<MedicalRecordDetail> setStatus({
    required String access,
    required String uid,
    required String status,
    String reason = '',
  }) async {
    final res = await _client
        .post(
          _uri(['medical-records', uid, 'status']),
          headers: _writeHeaders(access),
          body: jsonEncode({
            'status': status,
            if (reason.isNotEmpty) 'reason': reason,
          }),
        )
        .timeout(_timeout);
    return MedicalRecordDetail.fromJson(_body(res));
  }

  /// Per-record opt-out from the consent-derived read set.
  Future<MedicalRecordDetail> setVisibility({
    required String access,
    required String uid,
    required bool isConsentVisible,
  }) async {
    final res = await _client
        .post(
          _uri(['medical-records', uid, 'visibility']),
          headers: _writeHeaders(access),
          body: jsonEncode({'is_consent_visible': isConsentVisible}),
        )
        .timeout(_timeout);
    return MedicalRecordDetail.fromJson(_body(res));
  }

  /// Hand this one record to one named user, at the narrowest scope they need.
  Future<Map<String, dynamic>> share({
    required String access,
    required String uid,
    required String grantedToUid,
    String scope = 'view',
    String purpose = '',
    String? expiresAt,
  }) async {
    final res = await _client
        .post(
          _uri(['medical-records', uid, 'share']),
          headers: _writeHeaders(access),
          body: jsonEncode({
            'granted_to_uid': grantedToUid,
            'scope': scope,
            if (purpose.isNotEmpty) 'purpose': purpose,
            if (expiresAt != null && expiresAt.isNotEmpty) 'expires_at': expiresAt,
          }),
        )
        .timeout(_timeout);
    return _body(res);
  }

  /// Fetch a stored file's bytes. Authorized call, never a link.
  Future<List<int>> downloadFile({
    required String access,
    required MedicalRecordFile file,
  }) async {
    final res = await _client
        .get(
          _uri(['medical-records', 'files', file.uid, 'download']),
          headers: _headers(access),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode >= 400) throw _errorFrom(res);
    return res.bodyBytes;
  }
}