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

  bool get isPublished => status == 'PUBLISHED';
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