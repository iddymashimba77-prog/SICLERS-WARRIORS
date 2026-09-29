/// Public content client: news + announcements (unauthenticated reads).
///
/// Mirrors the backend `content` public surface exactly — envelope unwrapping,
/// paginated `results`, and error carving follow the shared conventions. This
/// repository never authenticates: public reads expose only PUBLISHED rows the
/// server already filtered.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../domain/content_models.dart';

class ContentException implements Exception {
  const ContentException(this.message, {this.code = 'API_ERROR', this.statusCode});

  final String message;
  final String code;
  final int? statusCode;

  @override
  String toString() => 'ContentException($code): $message';
}

class ContentRepository {
  ContentRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  Uri _uri(List<String> segments, {Map<String, String>? query}) =>
      Uri.parse('${AppConfig.apiBaseUrl}/${segments.join('/')}/')
          .replace(queryParameters: query);

  Map<String, dynamic> _envelope(http.Response res) {
    if (res.statusCode >= 400) {
      String message = 'Could not load content (${res.statusCode}).';
      String code = 'API_ERROR';
      try {
        final map = jsonDecode(res.body) as Map<String, dynamic>;
        final err = map['error'] as Map<String, dynamic>? ?? const {};
        message = (err['message'] as String?) ?? message;
        code = (err['code'] as String?) ?? code;
      } catch (_) {/* keep generic message */}
      throw ContentException(message, code: code, statusCode: res.statusCode);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) return data;
      if (data is List) return <String, dynamic>{'results': data};
      return decoded;
    }
    // Some public endpoints (ticker, categories) return a bare JSON list.
    return <String, dynamic>{'results': decoded is List ? decoded : const []};
  }

  /// Resolves backend-relative media URLs (`/media/...`) against the API
  /// origin so covers render on devices while the server stays the authority.
  String _resolveMedia(Map<String, dynamic> json, String key) {
    final raw = json[key];
    if (raw is! String || raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = Uri.parse(AppConfig.apiBaseUrl);
    final origin = Uri(scheme: base.scheme, host: base.host, port: base.port);
    return origin.resolve(raw).toString();
  }

  /// GET /api/content/news/ — published, paginated, filterable.
  Future<PublicContentPage> listNews({
    int page = 1,
    String? category,
    String? query,
    bool? featured,
  }) async {
    final res = await _client
        .get(
          _uri(
            ['content', 'news'],
            query: {
              'page': '$page',
              if (category != null && category.isNotEmpty) 'category': category,
              if (query != null && query.isNotEmpty) 'q': query,
              if (featured != null) 'featured': featured ? 'true' : 'false',
            },
          ),
        )
        .timeout(_timeout);
    final payload = _envelope(res);
    final results = payload['results'];
    return PublicContentPage(
      items: [
        for (final row in results is List ? results : const [])
          if (row is Map<String, dynamic>)
            _article(row),
      ],
      hasNext: payload['next'] is String,
    );
  }

  /// GET /api/content/news/latest/ — the newest published article (hero).
  Future<PublicNewsDetail?> latestArticle() async {
    final res = await _client
        .get(_uri(['content', 'news', 'latest']))
        .timeout(_timeout);
    final payload = _envelope(res);
    final article = payload['article'];
    if (article is! Map<String, dynamic>) return null;
    return _detail(article);
  }

  /// GET /api/content/news/categories/ — the taxonomy offered by the server.
  Future<List<NewsCategory>> listCategories() async {
    final res = await _client
        .get(_uri(['content', 'news', 'categories']))
        .timeout(_timeout);
    final payload = _envelope(res);
    final rows = payload is List ? payload : payload['results'];
    return [
      for (final row in rows is List ? rows : const [])
        if (row is Map<String, dynamic>) NewsCategory.fromJson(row),
    ];
  }

  /// GET /api/content/news/{uid}/ — single published article (full body).
  Future<PublicNewsDetail> getNews(String uid) async {
    final res =
        await _client.get(_uri(['content', 'news', uid])).timeout(_timeout);
    return _detail(_envelope(res));
  }

  /// GET /api/content/ticker/ — currently active announcements.
  Future<List<TickerAnnouncement>> listTicker() async {
    final res =
        await _client.get(_uri(['content', 'ticker'])).timeout(_timeout);
    final payload = _envelope(res);
    final rows = payload is List ? payload : payload['results'];
    return [
      for (final row in rows is List ? rows : const [])
        if (row is Map<String, dynamic>) TickerAnnouncement.fromJson(row),
    ];
  }

  PublicNewsArticle _article(Map<String, dynamic> json) => PublicNewsArticle.fromJson({
        ...json,
        if (json['cover_url'] is String) 'cover_url': _resolveMedia(json, 'cover_url'),
      });

  PublicNewsDetail _detail(Map<String, dynamic> json) => PublicNewsDetail.fromJson({
        ...json,
        if (json['cover_url'] is String) 'cover_url': _resolveMedia(json, 'cover_url'),
      });
}