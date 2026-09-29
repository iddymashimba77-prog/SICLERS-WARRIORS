/// Approved Stage 4.10 API client for `/api/chat/*`.
///
/// Mirrors database-design §15 (`conversations`, `conversation_participants`,
/// `messages`) and endpoint matrix §17. Conversation access is membership
/// scoped (C13): a non-participant never sees a conversation. v1 is not
/// end-to-end encrypted; TLS + server ACL is the designed level (§23).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../../auth/data/token_store.dart';
import '../../auth/domain/auth_types.dart';

class ChatUser {
  const ChatUser({required this.uid, required this.displayName});

  factory ChatUser.fromJson(Map<String, dynamic> json) => ChatUser(
        uid: (json['uid'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? 'Member',
      );

  final String uid;
  final String displayName;
}

class ChatParticipant {
  const ChatParticipant({
    required this.user,
    required this.roleInChat,
    required this.status,
  });

  factory ChatParticipant.fromJson(Map<String, dynamic> json) => ChatParticipant(
        user: ChatUser.fromJson((json['user'] as Map<String, dynamic>?) ?? const {}),
        roleInChat: (json['role_in_chat'] as String?) ?? 'MEMBER',
        status: (json['status'] as String?) ?? 'ACTIVE',
      );

  final ChatUser user;
  final String roleInChat;
  final String status;
}

class Conversation {
  const Conversation({
    required this.uid,
    required this.type,
    required this.status,
    required this.createdBy,
    required this.participants,
    required this.unreadCount,
    this.lastMessageAt,
    this.createdAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        uid: (json['uid'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'DOCTOR_PATIENT',
        status: (json['status'] as String?) ?? 'ACTIVE',
        createdBy: ChatUser.fromJson(
          (json['created_by'] as Map<String, dynamic>?) ?? const {},
        ),
        participants: [
          for (final p in (json['participants'] as List<dynamic>? ?? const []))
            ChatParticipant.fromJson(p as Map<String, dynamic>),
        ],
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
        lastMessageAt: json['last_message_at'] as String?,
        createdAt: json['created_at'] as String?,
      );

  final String uid;
  final String type;
  final String status;
  final ChatUser createdBy;
  final List<ChatParticipant> participants;
  final int unreadCount;
  final String? lastMessageAt;
  final String? createdAt;

  /// Participant names for a 1:1 thread (verified professional + patient).
  String get displayTitle {
    final names = participants
        .map((p) => p.user.displayName)
        .where((n) => n.isNotEmpty)
        .toList();
    return names.isEmpty ? 'Conversation' : names.join(' · ');
  }
}

class ChatMessage {
  const ChatMessage({
    required this.uid,
    required this.sender,
    required this.content,
    required this.messageType,
    required this.status,
    required this.deleted,
    required this.isMine,
    this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        uid: (json['uid'] as String?) ?? '',
        sender: ChatUser.fromJson((json['sender'] as Map<String, dynamic>?) ?? const {}),
        content: (json['content'] as String?) ?? '',
        messageType: (json['message_type'] as String?) ?? 'TEXT',
        status: (json['status'] as String?) ?? 'SENT',
        deleted: (json['deleted'] as bool?) ?? false,
        isMine: (json['is_mine'] as bool?) ?? false,
        createdAt: json['created_at'] as String?,
      );

  final String uid;
  final ChatUser sender;
  final String content;
  final String messageType;
  final String status;
  final bool deleted;
  final bool isMine;
  final String? createdAt;

  bool get isRead => status == 'READ';
}

class ChatRepository {
  ChatRepository({required this.tokenStore, http.Client? client})
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

  Future<List<Conversation>> listConversations({required String access}) async {
    final res = await _client
        .get(_uri(['chat', 'conversations']), headers: _headers(access))
        .timeout(_timeout);
    return _list(res)
        .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Conversation> startConversation({
    required String access,
    required String participantUid,
  }) async {
    final res = await _client
        .post(
          _uri(['chat', 'conversations']),
          headers: _headers(access),
          body: jsonEncode({'participant_uid': participantUid, 'type': 'DOCTOR_PATIENT'}),
        )
        .timeout(_timeout);
    return Conversation.fromJson(_body(res));
  }

  Future<Conversation> getConversation({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['chat', 'conversations', uid]), headers: _headers(access))
        .timeout(_timeout);
    return Conversation.fromJson(_body(res));
  }

  Future<List<ChatMessage>> listMessages({
    required String access,
    required String uid,
  }) async {
    final res = await _client
        .get(_uri(['chat', 'conversations', uid, 'messages']), headers: _headers(access))
        .timeout(_timeout);
    return _list(res)
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> sendMessage({
    required String access,
    required String uid,
    required String content,
  }) async {
    final res = await _client
        .post(
          _uri(['chat', 'conversations', uid, 'messages']),
          headers: _headers(access),
          body: jsonEncode({'content': content, 'message_type': 'TEXT'}),
        )
        .timeout(_timeout);
    return ChatMessage.fromJson(_body(res));
  }

  Future<void> deleteMessage({
    required String access,
    required String conversationUid,
    required String messageUid,
  }) async {
    final res = await _client
        .delete(
          _uri(['chat', 'conversations', conversationUid, 'messages', messageUid]),
          headers: _headers(access),
        )
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
  }

  Future<void> markRead({required String access, required String uid}) async {
    final res = await _client
        .post(_uri(['chat', 'conversations', uid, 'read']), headers: _headers(access))
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
  }

  Future<void> leaveConversation({required String access, required String uid}) async {
    final res = await _client
        .post(_uri(['chat', 'conversations', uid, 'leave']), headers: _headers(access))
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
  }
}
