/// Approved Stage 4.10 API client for `/api/community/*`.
///
/// Mirrors database-design §14 (`community_posts`, `comments`, `reactions`,
/// `reports`) and endpoint matrix §16. Deny by default: reads are open to
/// authenticated members; writes are gated; moderation is moderator-only.
/// Author projection is uid + display name only — no email/phone/PHI crosses
/// this boundary (data boundary §14).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

const List<String> communityCategories = [
  'SUPPORT',
  'EDUCATION',
  'GENERAL',
  'VENTING',
];

class CommunityAuthor {
  const CommunityAuthor({required this.uid, required this.displayName});

  factory CommunityAuthor.fromJson(Map<String, dynamic> json) => CommunityAuthor(
        uid: (json['uid'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? 'Member',
      );

  final String uid;
  final String displayName;
}

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.uid,
    required this.author,
    required this.title,
    required this.content,
    required this.category,
    required this.status,
    required this.reactionCount,
    required this.commentCount,
    required this.reacted,
    required this.isAuthor,
    this.moderationReason = '',
    this.createdAt,
    this.updatedAt,
  });

  factory CommunityPost.fromJson(Map<String, dynamic> json) => CommunityPost(
        id: (json['id'] as num?)?.toInt() ?? 0,
        uid: (json['uid'] as String?) ?? '',
        author: CommunityAuthor.fromJson(
          (json['author'] as Map<String, dynamic>?) ?? const {},
        ),
        title: (json['title'] as String?) ?? '',
        content: (json['content'] as String?) ?? '',
        category: (json['category'] as String?) ?? 'GENERAL',
        status: (json['status'] as String?) ?? 'PUBLISHED',
        moderationReason: (json['moderation_reason'] as String?) ?? '',
        reactionCount: (json['reaction_count'] as num?)?.toInt() ?? 0,
        commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
        reacted: (json['reacted'] as bool?) ?? false,
        isAuthor: (json['is_author'] as bool?) ?? false,
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  final int id;
  final String uid;
  final CommunityAuthor author;
  final String title;
  final String content;
  final String category;
  final String status;
  final String moderationReason;
  final int reactionCount;
  final int commentCount;
  final bool reacted;
  final bool isAuthor;
  final String? createdAt;
  final String? updatedAt;

  bool get isPublished => status == 'PUBLISHED';
}

class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.author,
    required this.content,
    required this.status,
    required this.isAuthor,
    this.createdAt,
  });

  factory CommunityComment.fromJson(Map<String, dynamic> json) =>
      CommunityComment(
        id: (json['id'] as num?)?.toInt() ?? 0,
        author: CommunityAuthor.fromJson(
          (json['author'] as Map<String, dynamic>?) ?? const {},
        ),
        content: (json['content'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'PUBLISHED',
        isAuthor: (json['is_author'] as bool?) ?? false,
        createdAt: json['created_at'] as String?,
      );

  final int id;
  final CommunityAuthor author;
  final String content;
  final String status;
  final bool isAuthor;
  final String? createdAt;
}

class ReportReceipt {
  const ReportReceipt({required this.id, required this.status});

  factory ReportReceipt.fromJson(Map<String, dynamic> json) => ReportReceipt(
        id: (json['id'] as num?)?.toInt() ?? 0,
        status: (json['status'] as String?) ?? 'OPEN',
      );

  final int id;
  final String status;
}

class CommunityRepository {
  CommunityRepository({required this.tokenStore, http.Client? client})
      : _client = client ?? http.Client();

  final TokenStore tokenStore;
  final http.Client _client;

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
    if (res.statusCode == 204 || res.body.isEmpty) return const {};
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return (map['data'] as Map<String, dynamic>?) ?? map;
  }

  List<dynamic> _list(http.Response res) {
    final payload = _body(res);
    final results = payload['results'];
    return results is List ? results : const [];
  }

  Future<List<CommunityPost>> listPosts({
    required String access,
    String? category,
    bool mine = false,
  }) async {
    final query = <String, String>{
      if (category != null && category.isNotEmpty) 'category': category,
      if (mine) 'author': 'me',
    };
    final uri = _uri(['community', 'posts']).replace(queryParameters: query.isEmpty ? null : query);
    final res = await _client.get(uri, headers: _headers(access)).timeout(_timeout);
    return _list(res)
        .map((e) => CommunityPost.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CommunityPost> createPost({
    required String access,
    required String content,
    String title = '',
    String category = 'GENERAL',
  }) async {
    final res = await _client
        .post(
          _uri(['community', 'posts']),
          headers: _headers(access),
          body: jsonEncode({'title': title, 'content': content, 'category': category}),
        )
        .timeout(_timeout);
    return CommunityPost.fromJson(_body(res));
  }

  Future<CommunityPost> getPost({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['community', 'posts', uid]), headers: _headers(access))
        .timeout(_timeout);
    return CommunityPost.fromJson(_body(res));
  }

  /// PATCH /community/posts/{uid}/ — author or moderator only (backend enforces).
  Future<CommunityPost> updatePost({
    required String access,
    required String uid,
    required String content,
    String title = '',
    String category = 'GENERAL',
  }) async {
    final res = await _client
        .patch(
          _uri(['community', 'posts', uid]),
          headers: _headers(access),
          body: jsonEncode(
            {'title': title, 'content': content, 'category': category},
          ),
        )
        .timeout(_timeout);
    return CommunityPost.fromJson(_body(res));
  }

  Future<void> deletePost({required String access, required String uid}) async {
    final res = await _client
        .delete(_uri(['community', 'posts', uid]), headers: _headers(access))
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
  }

  Future<Map<String, dynamic>> toggleReaction({
    required String access,
    required String uid,
    bool on = true,
    String reactionType = 'LIKE',
  }) async {
    final uri = _uri(['community', 'posts', uid, 'reactions']);
    final res = on
        ? await _client
            .post(uri, headers: _headers(access), body: jsonEncode({'reaction_type': reactionType}))
            .timeout(_timeout)
        : await _client
            .delete(uri, headers: _headers(access), body: jsonEncode({'reaction_type': reactionType}))
            .timeout(_timeout);
    return _body(res);
  }

  Future<List<CommunityComment>> listComments({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['community', 'posts', uid, 'comments']), headers: _headers(access))
        .timeout(_timeout);
    return _list(res)
        .map((e) => CommunityComment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CommunityComment> createComment({
    required String access,
    required String uid,
    required String content,
  }) async {
    final res = await _client
        .post(
          _uri(['community', 'posts', uid, 'comments']),
          headers: _headers(access),
          body: jsonEncode({'content': content}),
        )
        .timeout(_timeout);
    return CommunityComment.fromJson(_body(res));
  }

  Future<ReportReceipt> reportContent({
    required String access,
    required String targetType,
    required int targetId,
    required String reason,
  }) async {
    final res = await _client
        .post(
          _uri(['community', 'reports']),
          headers: _headers(access),
          body: jsonEncode({
            'target_type': targetType,
            'target_id': targetId,
            'reason': reason,
          }),
        )
        .timeout(_timeout);
    return ReportReceipt.fromJson(_body(res));
  }
}
