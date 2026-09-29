/// Public-facing news & announcement models.
///
/// Mirror the backend `content` public contract:
///
///   GET /api/content/news/            → { count, next, previous, results }
///   GET /api/content/news/latest/     → { article: {...} | null }
///   GET /api/content/news/categories/ → [ { code, label }, ... ]
///   GET /api/content/news/{uid}/      → single published article (with body)
///   GET /api/content/ticker/          → [ { message, ... }, ... ]
library;

class NewsCategory {
  const NewsCategory({required this.code, required this.label});

  factory NewsCategory.fromJson(Map<String, dynamic> json) => NewsCategory(
        code: _str(json['code']),
        label: _str(json['label']),
      );

  final String code;
  final String label;
}

class PublicNewsArticle {
  const PublicNewsArticle({
    required this.uid,
    required this.title,
    this.category = '',
    this.categoryLabel = '',
    this.excerpt = '',
    this.coverUrl = '',
    this.coverAlt = '',
    this.tags = const [],
    this.featured = false,
    this.publishedAt,
    this.authorName = '',
  });

  factory PublicNewsArticle.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>?;
    return PublicNewsArticle(
      uid: _str(json['uid']),
      title: _str(json['title']),
      category: _str(json['category']),
      categoryLabel: _str(json['category_label']),
      excerpt: _str(json['excerpt']),
      coverUrl: _str(json['cover_url']),
      coverAlt: _str(json['cover_alt']),
      tags: [...?(json['tags'] as List?)?.cast<String>()],
      featured: json['featured'] == true,
      publishedAt: json['published_at'] as String?,
      authorName: _str(author?['display_name']),
    );
  }

  final String uid;
  final String title;
  final String category;
  final String categoryLabel;
  final String excerpt;
  final String coverUrl;
  final String coverAlt;
  final List<String> tags;
  final bool featured;
  final String? publishedAt;
  final String authorName;
}

class PublicNewsDetail extends PublicNewsArticle {
  const PublicNewsDetail({
    required super.uid,
    required super.title,
    super.category,
    super.categoryLabel,
    super.excerpt,
    super.coverUrl,
    super.coverAlt,
    super.tags,
    super.featured,
    super.publishedAt,
    super.authorName,
    this.body = '',
  });

  factory PublicNewsDetail.fromJson(Map<String, dynamic> json) =>
      PublicNewsDetail(
        uid: _str(json['uid']),
        title: _str(json['title']),
        category: _str(json['category']),
        categoryLabel: _str(json['category_label']),
        excerpt: _str(json['excerpt']),
        coverUrl: _str(json['cover_url']),
        coverAlt: _str(json['cover_alt']),
        tags: [...?(json['tags'] as List?)?.cast<String>()],
        featured: json['featured'] == true,
        publishedAt: json['published_at'] as String?,
        authorName: _str((json['author'] as Map<String, dynamic>?)?['display_name']),
        body: _str(json['body']),
      );

  final String body;
}

class TickerAnnouncement {
  const TickerAnnouncement({
    required this.message,
    this.type = 'INFO',
    this.linkUrl = '',
  });

  factory TickerAnnouncement.fromJson(Map<String, dynamic> json) =>
      TickerAnnouncement(
        message: _str(json['message']),
        type: _str(json['announcement_type']),
        linkUrl: _str(json['link_url']),
      );

  final String message;
  final String type;
  final String linkUrl;

  bool get isUrgent => type == 'URGENT';
}

class PublicContentPage {
  const PublicContentPage({required this.items, required this.hasNext});

  final List<PublicNewsArticle> items;
  final bool hasNext;
}

String _str(dynamic value) => value is String ? value : (value?.toString() ?? '');