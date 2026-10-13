/// Approved Stage 4.11 API client for `/api/education/*`.
///
/// Mirrors the flat, approved model (`education_categories` (1) →
/// `educational_content` (N)) from database-design §17 and endpoint matrix
/// §18. The public read surface is published-only; drafts are locked server
/// side. Bookmarks are a LOCAL, session-only convenience (approved EDU-005):
/// nothing is sent to the server and they are lost on app restart.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

class EducationCategory {
  const EducationCategory({
    required this.id,
    required this.code,
    required this.name,
  });

  factory EducationCategory.fromJson(Map<String, dynamic> json) =>
      EducationCategory(
        id: (json['id'] as num?)?.toInt() ?? 0,
        code: (json['code'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
      );

  final int id;
  final String code;
  final String name;
}

class EducationAuthor {
  const EducationAuthor({required this.uid, required this.displayName});

  factory EducationAuthor.fromJson(Map<String, dynamic> json) => EducationAuthor(
        uid: (json['uid'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? 'Member',
      );

  final String uid;
  final String displayName;
}

/// Must stay in step with `education.models.EDITABLE_STATUSES`.
const _editableStatuses = <String>{'DRAFT', 'REJECTED', 'ARCHIVED'};

/// Must stay in step with `education.models.SUBMITTABLE_STATUSES`.
const _submittableStatuses = <String>{'DRAFT', 'REJECTED'};

class EducationalContent {
  const EducationalContent({
    required this.id,
    required this.uid,
    required this.author,
    required this.title,
    required this.body,
    required this.category,
    required this.status,
    this.coverUrl = '',
    this.publishedAt,
    this.createdAt,
    this.documentUrl,
    this.documentName = '',
    this.documentContentType = '',
    this.documentSize,
  });

  factory EducationalContent.fromJson(Map<String, dynamic> json) =>
      EducationalContent(
        id: (json['id'] as num?)?.toInt() ?? 0,
        uid: (json['uid'] as String?) ?? '',
        author: EducationAuthor.fromJson(
          (json['author'] as Map<String, dynamic>?) ?? const {},
        ),
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        category: EducationCategory.fromJson(
          (json['category'] as Map<String, dynamic>?) ?? const {},
        ),
        status: (json['status'] as String?) ?? 'PUBLISHED',
        coverUrl: (json['cover_url'] as String?) ?? '',
        publishedAt: (json['published_at'] as String?) ??
            (json['created_at'] as String?),
        createdAt: json['created_at'] as String?,
        documentUrl: json['document_url'] as String?,
        documentName: (json['document_name'] as String?) ?? '',
        documentContentType: (json['document_content_type'] as String?) ?? '',
        documentSize: (json['document_size'] as num?)?.toInt(),
      );

  final int id;
  final String uid;
  final EducationAuthor author;
  final String title;
  final String body;
  final EducationCategory category;
  final String status;
  final String coverUrl;
  final String? publishedAt;
  final String? createdAt;
  final String? documentUrl;
  final String documentName;
  final String documentContentType;
  final int? documentSize;

  bool get isPublished => status == 'PUBLISHED';

  /// True once the article carries a downloadable handout.
  bool get hasDocument => (documentUrl ?? '').isNotEmpty;

  /// A published article is frozen: the server refuses any handout change
  /// until an admin unpublishes it, so the UI must not offer one.
  bool get canChangeDocument => !isPublished;

  /// Mirrors `education.models.EDITABLE_STATUSES`. An in-review or published
  /// article is owned by the reviewers, so the author cannot quietly rewrite it.
  bool get canEdit => _editableStatuses.contains(status);

  /// Mirrors `education.models.SUBMITTABLE_STATUSES`. Archived content has to
  /// be resubmitted through the archive path, not straight back into review.
  bool get canSubmit => _submittableStatuses.contains(status);

  /// A draft that was never public can be hard-deleted (EDU-005); anything
  /// else keeps its review history.
  bool get canDelete => status == 'DRAFT';

  bool get isEditableDraft => canEdit && !isPublished;

  String get readableDocumentSize {
    final bytes = documentSize;
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// A local file chosen on the device, ready to be sent as a handout.
class DocumentUpload {
  const DocumentUpload({
    required this.path,
    required this.filename,
    required this.sizeBytes,
  });

  final String path;
  final String filename;
  final int sizeBytes;

  static const allowedExtensions = <String>[
    'pdf',
    'pptx',
    'docx',
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  static const maxBytes = 20 * 1024 * 1024;

  String get extension {
    final dot = filename.lastIndexOf('.');
    return dot == -1 ? '' : filename.substring(dot + 1).toLowerCase();
  }

  /// Mirrors ``education.services.DOCUMENT_ALLOWED_EXTENSIONS``. Checking on
  /// the device saves the user a slow upload the server would only reject.
  bool get hasAllowedExtension => allowedExtensions.contains(extension);

  bool get isWithinSizeLimit => sizeBytes > 0 && sizeBytes <= maxBytes;

  /// Human-readable rejection reason, or null when the file can be sent.
  String? get rejectionReason {
    if (!hasAllowedExtension) {
      return 'Choose a PDF, PPTX, DOCX, JPEG, PNG or WebP file.';
    }
    if (sizeBytes <= 0) return 'That file is empty.';
    if (!isWithinSizeLimit) return 'That file is larger than 20 MB.';
    return null;
  }
}

class EducationRepository {
  EducationRepository({required this.tokenStore, http.Client? client})
      : _client = client ?? http.Client();

  final TokenStore tokenStore;
  final http.Client _client;

  /// Session-local bookmarks (approved EDU-005). No server contact; not
  /// persisted across app restarts.
  final Set<String> _bookmarked = <String>{};

  static const _timeout = Duration(seconds: 15);

  Uri _uri(List<String> segments) =>
      Uri.parse('${AppConfig.apiBaseUrl}/${segments.join('/')}/');

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

  Map<String, dynamic> _body(http.Response res) {
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    if (res.statusCode == 204 || res.body.isEmpty) return const {};
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return (map['data'] as Map<String, dynamic>?) ?? map;
  }

  List<dynamic> _list(http.Response res) {
    final payload = _body(res);
    final results = payload['results'];
    return results is List ? results : const [];
  }

  Future<List<EducationCategory>> listCategories({required String access}) async {
    final res = await _client
        .get(_uri(['education', 'categories']), headers: _headers(access))
        .timeout(_timeout);
    return _list(res)
        .map((e) => EducationCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<EducationalContent>> listContent({
    required String access,
    String? query,
    String? category,
    int? page,
    int? pageSize,
  }) async {
    final params = <String, String>{
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (category != null && category.isNotEmpty) 'category': category,
      // Server caps page_size at 100 (NFR-PERF-002); requesters may ask for a
      // specific page to enable pagination.
      if (page != null) 'page': '$page',
      if (pageSize != null && pageSize > 0) 'page_size': '$pageSize',
    };
    final uri = _uri(['education', 'content'])
        .replace(queryParameters: params.isEmpty ? null : params);
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _list(res)
        .map((e) => EducationalContent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EducationalContent> getContent({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['education', 'content', uid]), headers: _headers(access))
        .timeout(_timeout);
    return EducationalContent.fromJson(_body(res));
  }

  // --- Author workspace (doctor side, FR-EDU-005) ---------------------------

  /// The signed-in author's own articles in every status — the doctor-side
  /// counterpart to the public feed, which only ever returns PUBLISHED rows.
  Future<List<EducationalContent>> listMyContent({
    required String access,
    String? status,
  }) async {
    final params = <String, String>{'mine': '1'};
    if (status != null && status.isNotEmpty) params['status'] = status;
    final uri = _uri(['education', 'content'])
        .replace(queryParameters: params);
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _list(res)
        .map((e) => EducationalContent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Create a draft article. The server sanitises the title/body and rejects a
  /// category code it does not know, so the form sends codes, not labels.
  Future<EducationalContent> createContent({
    required String access,
    required String title,
    required String body,
    required String category,
    String coverUrl = '',
  }) async {
    final res = await _client
        .post(
          _uri(['education', 'content']),
          headers: _headers(access),
          body: jsonEncode({
            'title': title,
            'body': body,
            'category': category,
            if (coverUrl.isNotEmpty) 'cover_url': coverUrl,
          }),
        )
        .timeout(_timeout);
    return EducationalContent.fromJson(_body(res));
  }

  /// Patch an existing article. Only the fields passed are sent, so an edit
  /// that changes the title does not blank the cover URL the author set earlier.
  Future<EducationalContent> updateContent({
    required String access,
    required String uid,
    required String title,
    required String body,
    required String category,
    String? coverUrl,
  }) async {
    final res = await _client
        .patch(
          _uri(['education', 'content', uid]),
          headers: _headers(access),
          body: jsonEncode({
            'title': title,
            'body': body,
            'category': category,
            if (coverUrl != null) 'cover_url': coverUrl,
          }),
        )
        .timeout(_timeout);
    return EducationalContent.fromJson(_body(res));
  }

  /// Send the article to the review queue. Only DRAFT/REJECTED may be sent.
  Future<EducationalContent> submitContent({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .post(
          _uri(['education', 'content', uid, 'submit']),
          headers: _headers(access),
          body: '{}',
        )
        .timeout(_timeout);
    return EducationalContent.fromJson(_body(res));
  }

  /// Delete a never-published draft.
  Future<void> deleteContent({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .delete(_uri(['education', 'content', uid]), headers: _headers(access))
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
  }

  /// Attach or replace the article handout. Multipart, so the file is streamed
  /// with an explicit boundary and no `Content-Type: application/json`.
  Future<EducationalContent> uploadDocument({
    required String access,
    required String uid,
    required DocumentUpload upload,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri(['education', 'content', uid, 'document']),
    )
      ..headers['Accept'] = 'application/json'
      ..headers['Authorization'] = 'Bearer $access'
      ..files.add(await http.MultipartFile.fromPath(
        'document',
        upload.path,
        filename: upload.filename,
      ));
    // A deck on a slow clinic connection can take a while to send.
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    return EducationalContent.fromJson(_body(res));
  }

  /// Detach the handout. The stored file is deleted server-side.
  Future<EducationalContent> removeDocument({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .delete(
          _uri(['education', 'content', uid, 'document']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return EducationalContent.fromJson(_body(res));
  }

  // --- Session-local bookmarks (EDU-005) -----------------------------------
  bool isBookmarked(String uid) => _bookmarked.contains(uid);

  List<String> get bookmarkedUids => _bookmarked.toList(growable: false);

  bool get hasBookmarks => _bookmarked.isNotEmpty;

  bool toggleBookmark(String uid) {
    if (_bookmarked.contains(uid)) {
      _bookmarked.remove(uid);
      return false;
    }
    _bookmarked.add(uid);
    return true;
  }
}