/// Client for the AI assistant surface (`/api/ai/chat/`, api-design AD-2).
///
/// One endpoint, one use-case switch — mirrors `backend/ai_assistant/serializers.py`:
///
///   POST /api/ai/chat/
///   {message, use_case, personalized, metric?}
///
/// The response is the single `_finish()` envelope produced by
/// `AiAssistantService`: generated text plus the safety, provenance and
/// disclaimer fields the UI is required to surface (FR-AI-006). Nothing about
/// the payload is invented client-side.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';

/// Approved-knowledge citation attached to an answer.
class AiSource {
  const AiSource({
    required this.uid,
    required this.title,
    required this.snippet,
    this.score = 0,
  });

  factory AiSource.fromJson(Map<String, dynamic> json) => AiSource(
        uid: (json['uid'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        snippet: (json['snippet'] as String?) ?? '',
        score: (json['score'] as num?)?.toInt() ?? 0,
      );

  final String uid;
  final String title;
  final String snippet;
  final int score;
}

/// One assistant turn exactly as the backend scored it.
class AiChatTurn {
  const AiChatTurn({
    required this.assistantId,
    required this.useCase,
    required this.message,
    required this.disclaimer,
    this.personalized = false,
    this.emergencyAction = false,
    this.emergencyCategories = const [],
    this.safetyBlocked = false,
    this.safetyReason,
    this.contextUsed = false,
    this.limitation,
    this.sources = const [],
    this.metrics,
  });

  factory AiChatTurn.fromJson(Map<String, dynamic> json) {
    final safety = json['safety'] as Map<String, dynamic>? ?? const {};
    return AiChatTurn(
      assistantId: (json['assistant_id'] as String?) ?? '',
      useCase: (json['use_case'] as String?) ?? 'education',
      message: (json['message'] as String?) ?? '',
      disclaimer: (json['disclaimer'] as String?) ?? '',
      personalized: json['personalized'] == true,
      emergencyAction: json['emergency_action'] == true,
      emergencyCategories: [
        for (final c in (json['emergency_categories'] as List<dynamic>? ?? const []))
          c.toString(),
      ],
      safetyBlocked: safety['blocked'] == true,
      safetyReason: safety['reason'] as String?,
      contextUsed: json['context_used'] == true,
      limitation: json['limitation'] as String?,
      sources: [
        for (final s in (json['sources'] as List<dynamic>? ?? const []))
          AiSource.fromJson((s as Map<String, dynamic>?) ?? const {}),
      ],
      metrics: json['metrics'] as Map<String, dynamic>?,
    );
  }

  final String assistantId;
  final String useCase;
  final String message;
  final String disclaimer;
  final bool personalized;
  final bool emergencyAction;
  final List<String> emergencyCategories;
  final bool safetyBlocked;
  final String? safetyReason;
  final bool contextUsed;
  final String? limitation;
  final List<AiSource> sources;
  final Map<String, dynamic>? metrics;
}

/// Backend error in the project's `{"error": {...}}` envelope.
class AiRepositoryException implements Exception {
  const AiRepositoryException(this.message,
      {this.code = 'API_ERROR', this.statusCode = 0});

  final String message;
  final String code;
  final int statusCode;

  /// DRF rate-limits the chat surface to 6 turns/min/user (AD-9).
  bool get isThrottled => statusCode == 429;

  @override
  String toString() => message;
}

class AiRepository {
  AiRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Head-room over the rule-based sandbox: an external provider can be slow.
  static const _timeout = Duration(seconds: 30);

  Uri get _chatUri => Uri.parse('${AppConfig.apiBaseUrl}/ai/chat/');

  Map<String, String> _headers(String access) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $access',
      };

  AiRepositoryException _errorFrom(http.Response res) {
    try {
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final err = map['error'] as Map<String, dynamic>? ?? const {};
      return AiRepositoryException(
        (err['message'] as String?) ?? 'Request failed.',
        code: (err['code'] as String?) ?? 'API_ERROR',
        statusCode: res.statusCode,
      );
    } catch (_) {
      return AiRepositoryException(
        res.statusCode >= 500
            ? 'Server error. Please try again shortly.'
            : 'Request failed (${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }
  }

  /// POST /api/ai/chat/ — one assistant turn.
  Future<AiChatTurn> sendChat({
    required String access,
    required String message,
    String useCase = 'education',
    bool personalized = true,
    String? metric,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'use_case': useCase,
      'personalized': personalized,
    };
    if (metric != null) body['metric'] = metric;

    final res = await _client
        .post(_chatUri, headers: _headers(access), body: jsonEncode(body))
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res);
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>? ?? map;
    return AiChatTurn.fromJson(data);
  }
}
