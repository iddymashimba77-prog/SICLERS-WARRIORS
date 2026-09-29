import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sicklers_warriors/core/constants/app_strings.dart';
import 'package:sicklers_warriors/features/auth/data/token_store.dart';
import 'package:sicklers_warriors/features/chat/data/chat_repository.dart';
import 'package:sicklers_warriors/features/chat/presentation/pages/conversation_thread_page.dart';
import 'package:sicklers_warriors/features/community/data/community_repository.dart';
import 'package:sicklers_warriors/features/community/presentation/pages/community_create_post_page.dart';
import 'package:sicklers_warriors/features/community/presentation/pages/community_page.dart';

const _token = 'test-access';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> _postJson({
  String uid = 'post-1',
  int id = 1,
  String title = 'Hello warriors',
  String content = 'Stay strong together',
  String category = 'SUPPORT',
  String status = 'PUBLISHED',
  int reactionCount = 0,
  int commentCount = 0,
  bool reacted = false,
  bool isAuthor = false,
}) =>
    {
      'id': id,
      'uid': uid,
      'author': {'uid': 'u-1', 'display_name': 'Ama'},
      'title': title,
      'content': content,
      'category': category,
      'status': status,
      'moderation_reason': '',
      'reaction_count': reactionCount,
      'comment_count': commentCount,
      'reacted': reacted,
      'is_author': isAuthor,
      'created_at': '2026-09-18T08:00:00Z',
    };

Map<String, dynamic> _commentJson() => {
      'id': 7,
      'author': {'uid': 'u-2', 'display_name': 'Kofi'},
      'content': 'Praying for you',
      'status': 'PUBLISHED',
      'is_author': false,
      'created_at': '2026-09-18T09:00:00Z',
    };

Map<String, dynamic> _messageJson({
  String uid = 'msg-1',
  String content = 'How are you feeling?',
  bool isMine = false,
  bool deleted = false,
}) =>
    {
      'uid': uid,
      'conversation_uid': 'conv-1',
      'sender': {'uid': isMine ? 'me' : 'doc-1', 'display_name': isMine ? 'Me' : 'Dr. Mensah'},
      'content': content,
      'message_type': 'TEXT',
      'status': 'SENT',
      'deleted': deleted,
      'is_mine': isMine,
      'created_at': '2026-09-18T10:00:00Z',
    };

void main() {
  final store = EphemeralTokenStore();

  group('CommunityRepository (Stage 4.10)', () {
    test('listPosts parses posts and unwraps envelope', () async {
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer $_token');
        expect(request.url.path, '/api/community/posts/');
        return _json({
          'data': {
            'results': [_postJson(reactionCount: 3, reacted: true)]
          }
        });
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      final posts = await repo.listPosts(access: _token);
      expect(posts, hasLength(1));
      expect(posts.first.author.displayName, 'Ama');
      expect(posts.first.reactionCount, 3);
      expect(posts.first.reacted, isTrue);
    });

    test('createPost + reportContent send expected bodies', () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/api/community/posts/') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['content'], 'Hello');
          expect(body['category'], 'SUPPORT');
          return _json({'data': _postJson()}, 201);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['target_type'], 'POST');
        expect(body['target_id'], 1);
        expect(body['reason'], 'spam');
        return _json({'data': {'id': 9, 'status': 'OPEN'}}, 201);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      await repo.createPost(access: _token, content: 'Hello', category: 'SUPPORT');
      await repo.reportContent(
        access: _token,
        targetType: 'POST',
        targetId: 1,
        reason: 'spam',
      );
      expect(calls, [
        'POST /api/community/posts/',
        'POST /api/community/reports/',
      ]);
    });
    test('listComments + createComment hit approved paths', () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'GET') {
          return _json({
            'data': {
              'results': [_commentJson()]
            }
          });
        }
        return _json({'data': _commentJson()}, 201);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      final comments = await repo.listComments(access: _token, uid: 'post-1');
      expect(comments.single.author.displayName, 'Kofi');
      await repo.createComment(access: _token, uid: 'post-1', content: 'Amen');
      expect(calls, [
        'GET /api/community/posts/post-1/comments/',
        'POST /api/community/posts/post-1/comments/',
      ]);
    });
  });

  group('ChatRepository (Stage 4.10)', () {
    test('listConversations parses unread + display title', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/chat/conversations/');
        return _json({
          'data': {
            'results': [
              {
                'uid': 'conv-1',
                'type': 'DOCTOR_PATIENT',
                'status': 'ACTIVE',
                'created_by': {'uid': 'me', 'display_name': 'Me'},
                'participants': [
                  {'user': {'uid': 'doc-1', 'display_name': 'Dr. Mensah'}, 'role_in_chat': 'DOCTOR', 'status': 'ACTIVE'},
                  {'user': {'uid': 'me', 'display_name': 'Me'}, 'role_in_chat': 'PATIENT', 'status': 'ACTIVE'},
                ],
                'unread_count': 2,
                'last_message_at': '2026-09-18T10:00:00Z',
              }
            ]
          }
        });
      });
      final repo = ChatRepository(tokenStore: store, client: client);
      final conversations = await repo.listConversations(access: _token);
      expect(conversations.single.unreadCount, 2);
      expect(conversations.single.displayTitle, 'Dr. Mensah · Me');
    });

    test('sendMessage + deleteMessage hit approved paths', () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'POST') {
          return _json({'data': _messageJson(isMine: true)}, 201);
        }
        return http.Response('', 204);
      });
      final repo = ChatRepository(tokenStore: store, client: client);
      await repo.sendMessage(access: _token, uid: 'conv-1', content: 'Hi');
      await repo.deleteMessage(
        access: _token,
        conversationUid: 'conv-1',
        messageUid: 'msg-1',
      );
      expect(calls, [
        'POST /api/chat/conversations/conv-1/messages/',
        'DELETE /api/chat/conversations/conv-1/messages/msg-1/',
      ]);
    });
  });

  group('Community widgets (Stage 4.10)', () {
    testWidgets('feed renders posts and toggles a reaction', (tester) async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/community/posts/') {
          return _json({
            'data': {
              'results': [_postJson(reactionCount: 0)]
            }
          });
        }
        if (request.url.path == '/api/community/posts/post-1/reactions/') {
          return _json({
            'data': {'uid': 'post-1', 'reaction_count': 1, 'reacted': true}
          });
        }
        return http.Response('not found', 404);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      await tester.pumpWidget(MaterialApp(
        home: CommunityFeedView(accessToken: _token, repository: repo),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Hello warriors'), findsOneWidget);
      await tester.tap(find.textContaining(AppStrings.likePost).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Support 1'), findsOneWidget);
    });

    testWidgets('create post publishes via the repository', (tester) async {
      var posted = false;
      final client = MockClient((request) async {
        posted = true;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['content'], 'New support post');
        return _json({'data': _postJson(content: 'New support post')}, 201);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      await tester.pumpWidget(MaterialApp(
        home: CommunityCreatePostView(accessToken: _token, repository: repo),
      ));
      await tester.enterText(
        find.widgetWithText(TextField, AppStrings.postContent),
        'New support post',
      );
      await tester.tap(find.text(AppStrings.publishPost));
      await tester.pumpAndSettle();
      expect(posted, isTrue);
    });
  });

  group('Chat widgets (Stage 4.10)', () {
    testWidgets('thread loads messages and sends a reply', (tester) async {
      var sent = false;
      final client = MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/chat/conversations/conv-1/messages/') {
          return _json({
            'data': {
              'results': [_messageJson(content: 'How are you feeling?')]
            }
          });
        }
        if (request.url.path == '/api/chat/conversations/conv-1/read/') {
          return _json({'data': {'updated': 1}});
        }
        if (request.method == 'POST') {
          sent = true;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['content'], 'Much better today');
          return _json({'data': _messageJson(uid: 'msg-2', content: 'Much better today', isMine: true)}, 201);
        }
        return http.Response('not found', 404);
      });
      final repo = ChatRepository(tokenStore: store, client: client);
      await tester.pumpWidget(MaterialApp(
        home: ConversationThreadView(
          accessToken: _token,
          repository: repo,
          conversationUid: 'conv-1',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('How are you feeling?'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Much better today');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(sent, isTrue);
      expect(find.text('Much better today'), findsOneWidget);
    });
  });
}
