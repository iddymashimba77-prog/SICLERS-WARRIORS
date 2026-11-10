/// API client for `/api/community/*` (Stage 4.10 forum extension).
///
/// Mirrors database-design §14 (`community_posts`, `comments`, `reactions`,
/// `reports`, `forum_categories`) and endpoint matrix §16. Reads are open to
/// authenticated members; writes are gated; moderation is moderator-only.
/// Author projection is uid + display name only — no email/phone/PHI crosses
/// this boundary. Admin roles are rejected by the backend and hidden in routing.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';
import '../../notifications/data/notifications_repository.dart'
    show AppNotification;

/// Legacy labels retained for backward-compatible callers/tests only.
const List<String> communityCategories = [
  'SUPPORT',
  'EDUCATION',
  'GENERAL',
  'VENTING',
];

class CommunityAuthor {
  const CommunityAuthor({required this.uid, required this.displayName});

  factory CommunityAuthor.fromJson(Map<String, dynamic> json) =>
      CommunityAuthor(
        uid: (json['uid'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? 'Member',
      );

  final String uid;
  final String displayName;
}

class ForumCategory {
  const ForumCategory({
    required this.uid,
    required this.slug,
    required this.name,
    this.description = '',
    this.legacyCode = '',
    this.isActive = true,
    this.sortOrder = 0,
    this.postCount = 0,
  });

  factory ForumCategory.fromJson(Map<String, dynamic> json) => ForumCategory(
    uid: (json['uid'] as String?) ?? '',
    slug: (json['slug'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    description: (json['description'] as String?) ?? '',
    legacyCode: (json['legacy_code'] as String?) ?? '',
    isActive: (json['is_active'] as bool?) ?? true,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    postCount: (json['post_count'] as num?)?.toInt() ?? 0,
  );

  final String uid;
  final String slug;
  final String name;
  final String description;
  final String legacyCode;
  final bool isActive;
  final int sortOrder;
  final int postCount;
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
    this.authorRole = 'Member',
    this.forumCategory,
    this.categorySlug = '',
    this.isPinned = false,
    this.isLocked = false,
    this.isEdited = false,
    this.canModerate = false,
    this.lastActivityAt,
    this.moderationReason = '',
    this.createdAt,
    this.updatedAt,
  });

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    final category = (json['category'] as String?) ?? 'GENERAL';
    final forum = json['forum_category'] is Map<String, dynamic>
        ? ForumCategory.fromJson(json['forum_category'] as Map<String, dynamic>)
        : null;
    return CommunityPost(
      id: (json['id'] as num?)?.toInt() ?? 0,
      uid: (json['uid'] as String?) ?? '',
      author: CommunityAuthor.fromJson(
        (json['author'] as Map<String, dynamic>?) ?? const {},
      ),
      authorRole: (json['author_role'] as String?) ?? 'Member',
      title: (json['title'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      category: category,
      forumCategory: forum,
      categorySlug:
          (json['category_slug'] as String?) ??
          (forum?.slug.isNotEmpty == true
              ? forum!.slug
              : category.toLowerCase()),
      status: (json['status'] as String?) ?? 'PUBLISHED',
      isPinned: json['is_pinned'] == true,
      isLocked: json['is_locked'] == true,
      isEdited: json['is_edited'] == true,
      canModerate: json['can_moderate'] == true,
      lastActivityAt: json['last_activity_at'] as String?,
      moderationReason: (json['moderation_reason'] as String?) ?? '',
      reactionCount: (json['reaction_count'] as num?)?.toInt() ?? 0,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      reacted: (json['reacted'] as bool?) ?? false,
      isAuthor: (json['is_author'] as bool?) ?? false,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  final int id;
  final String uid;
  final CommunityAuthor author;
  final String authorRole;
  final String title;
  final String content;
  final String category;
  final ForumCategory? forumCategory;
  final String categorySlug;
  final String status;
  final bool isPinned;
  final bool isLocked;
  final bool isEdited;
  final bool canModerate;
  final String? lastActivityAt;
  final String moderationReason;
  final int reactionCount;
  final int commentCount;
  final bool reacted;
  final bool isAuthor;
  final String? createdAt;
  final String? updatedAt;

  bool get isPublished => status == 'PUBLISHED';

  String get categoryLabel =>
      forumCategory?.name.isNotEmpty == true ? forumCategory!.name : category;

  CommunityPost copyWith({
    String? title,
    String? content,
    String? category,
    ForumCategory? forumCategory,
    String? categorySlug,
    bool? isPinned,
    bool? isLocked,
    bool? isEdited,
    int? reactionCount,
    int? commentCount,
    bool? reacted,
  }) => CommunityPost(
    id: id,
    uid: uid,
    author: author,
    authorRole: authorRole,
    title: title ?? this.title,
    content: content ?? this.content,
    category: category ?? this.category,
    forumCategory: forumCategory ?? this.forumCategory,
    categorySlug: categorySlug ?? this.categorySlug,
    status: status,
    isPinned: isPinned ?? this.isPinned,
    isLocked: isLocked ?? this.isLocked,
    isEdited: isEdited ?? this.isEdited,
    canModerate: canModerate,
    lastActivityAt: lastActivityAt,
    moderationReason: moderationReason,
    reactionCount: reactionCount ?? this.reactionCount,
    commentCount: commentCount ?? this.commentCount,
    reacted: reacted ?? this.reacted,
    isAuthor: isAuthor,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

class CommunityPostPage {
  const CommunityPostPage({
    required this.posts,
    required this.count,
    required this.page,
    required this.hasMore,
  });

  final List<CommunityPost> posts;
  final int count;
  final int page;
  final bool hasMore;
}

class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.author,
    required this.content,
    required this.status,
    required this.isAuthor,
    this.authorRole = 'Member',
    this.parentId,
    this.depth = 1,
    this.isEdited = false,
    this.isDeleted = false,
    this.replyCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory CommunityComment.fromJson(Map<String, dynamic> json) =>
      CommunityComment(
        id: (json['id'] as num?)?.toInt() ?? 0,
        author: CommunityAuthor.fromJson(
          (json['author'] as Map<String, dynamic>?) ?? const {},
        ),
        authorRole: (json['author_role'] as String?) ?? 'Member',
        content: (json['content'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'PUBLISHED',
        parentId: (json['parent_id'] as num?)?.toInt(),
        depth: (json['depth'] as num?)?.toInt() ?? 1,
        isEdited: json['is_edited'] == true,
        isDeleted: json['is_deleted'] == true || json['status'] != 'PUBLISHED',
        replyCount: (json['reply_count'] as num?)?.toInt() ?? 0,
        isAuthor: (json['is_author'] as bool?) ?? false,
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  final int id;
  final CommunityAuthor author;
  final String authorRole;
  final String content;
  final String status;
  final int? parentId;
  final int depth;
  final bool isEdited;
  final bool isDeleted;
  final int replyCount;
  final bool isAuthor;
  final String? createdAt;
  final String? updatedAt;
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
        fieldErrors[field] = [
          for (final m in msgs is List ? msgs : [msgs]) '$m',
        ];
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

  Future<CommunityPostPage> listPostsPage({
    required String access,
    String? category,
    bool mine = false,
    String search = '',
    String sort = 'latest',
    int page = 1,
    int? pageSize,
  }) async {
    final query = <String, String>{
      if (category != null && category.isNotEmpty) 'category': category,
      if (mine) 'author': 'me',
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (sort.isNotEmpty && sort != 'latest') 'sort': sort,
      if (page > 1) 'page': '$page',
      if (pageSize != null) 'page_size': '$pageSize',
    };
    final uri = _uri([
      'community',
      'posts',
    ]).replace(queryParameters: query.isEmpty ? null : query);
    final res = await _client
        .get(uri, headers: _headers(access))
        .timeout(_timeout);
    final payload = _body(res);
    final raw = payload['results'];
    final posts = raw is List
        ? raw
              .map((e) => CommunityPost.fromJson(e as Map<String, dynamic>))
              .toList()
        : <CommunityPost>[];
    return CommunityPostPage(
      posts: posts,
      count: (payload['count'] as num?)?.toInt() ?? posts.length,
      page: page,
      hasMore:
          payload['next'] is String && (payload['next'] as String).isNotEmpty,
    );
  }

  Future<List<CommunityPost>> listPosts({
    required String access,
    String? category,
    bool mine = false,
    String search = '',
    String sort = 'latest',
  }) async {
    final page = await listPostsPage(
      access: access,
      category: category,
      mine: mine,
      search: search,
      sort: sort,
    );
    return page.posts;
  }

  Future<List<ForumCategory>> listCategories({required String access}) async {
    final res = await _client
        .get(_uri(['community', 'categories']), headers: _headers(access))
        .timeout(_timeout);
    return _list(
      res,
    ).map((e) => ForumCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CommunityPost> createPost({
    required String access,
    required String content,
    String title = '',
    String category = 'GENERAL',
    String? categorySlug,
  }) async {
    final body = <String, dynamic>{'title': title, 'content': content};
    if (categorySlug != null && categorySlug.isNotEmpty) {
      body['category_slug'] = categorySlug;
    } else {
      body['category'] = category;
    }
    final res = await _client
        .post(
          _uri(['community', 'posts']),
          headers: _headers(access),
          body: jsonEncode(body),
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

  /// PATCH /community/posts/{uid}/ — author or moderator only (backend enforced).
  Future<CommunityPost> updatePost({
    required String access,
    required String uid,
    required String content,
    String title = '',
    String category = 'GENERAL',
    String? categorySlug,
  }) async {
    final body = <String, dynamic>{'title': title, 'content': content};
    if (categorySlug != null && categorySlug.isNotEmpty) {
      body['category_slug'] = categorySlug;
    } else {
      body['category'] = category;
    }
    final res = await _client
        .patch(
          _uri(['community', 'posts', uid]),
          headers: _headers(access),
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    return CommunityPost.fromJson(_body(res));
  }

  Future<CommunityPost> setPostFlags({
    required String access,
    required String uid,
    bool? isPinned,
    bool? isLocked,
  }) async {
    if (isPinned == null && isLocked == null) {
      throw ArgumentError('At least one flag is required.');
    }
    final action = isPinned != null ? 'pin' : 'lock';
    final body = isPinned != null
        ? {'is_pinned': isPinned}
        : {'is_locked': isLocked};
    final res = await _client
        .post(
          _uri(['community', 'posts', uid, action]),
          headers: _headers(access),
          body: jsonEncode(body),
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
              .post(
                uri,
                headers: _headers(access),
                body: jsonEncode({'reaction_type': reactionType}),
              )
              .timeout(_timeout)
        : await _client
              .delete(
                uri,
                headers: _headers(access),
                body: jsonEncode({'reaction_type': reactionType}),
              )
              .timeout(_timeout);
    return _body(res);
  }

  Future<List<CommunityComment>> listComments({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(
          _uri(['community', 'posts', uid, 'comments']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return _list(
      res,
    ).map((e) => CommunityComment.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CommunityComment> createComment({
    required String access,
    required String uid,
    required String content,
    int? parentId,
  }) async {
    final body = <String, dynamic>{'content': content};
    if (parentId != null) body['parent_id'] = parentId;
    final res = await _client
        .post(
          _uri(['community', 'posts', uid, 'comments']),
          headers: _headers(access),
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    return CommunityComment.fromJson(_body(res));
  }

  Future<CommunityComment> updateComment({
    required String access,
    required String uid,
    required int commentId,
    required String content,
  }) async {
    final res = await _client
        .patch(
          _uri(['community', 'posts', uid, 'comments', '$commentId']),
          headers: _headers(access),
          body: jsonEncode({'content': content}),
        )
        .timeout(_timeout);
    return CommunityComment.fromJson(_body(res));
  }

  Future<void> deleteComment({
    required String access,
    required String uid,
    required int commentId,
  }) async {
    final res = await _client
        .delete(
          _uri(['community', 'posts', uid, 'comments', '$commentId']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
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

  Future<List<AppNotification>> listForumNotifications({
    required String access,
    bool unreadOnly = false,
  }) async {
    final uri = _uri([
      'community',
      'notifications',
    ]).replace(queryParameters: unreadOnly ? const {'unread': '1'} : null);
    final res = await _client
        .get(uri, headers: _headers(access))
        .timeout(_timeout);
    return _list(
      res,
    ).map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<int> forumUnreadCount({required String access}) async {
    final res = await _client
        .get(
          _uri(['community', 'notifications', 'unread-count']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return (_body(res)['unread'] as num?)?.toInt() ?? 0;
  }

  Future<AppNotification> markForumNotificationRead({
    required String access,
    required int id,
  }) async {
    final res = await _client
        .post(
          _uri(['community', 'notifications', '$id', 'read']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return AppNotification.fromJson(_body(res));
  }

  Future<int> markAllForumNotificationsRead({required String access}) async {
    final res = await _client
        .post(
          _uri(['community', 'notifications', 'read-all']),
          headers: _headers(access),
        )
        .timeout(_timeout);
    return (_body(res)['updated'] as num?)?.toInt() ?? 0;
  }
}
