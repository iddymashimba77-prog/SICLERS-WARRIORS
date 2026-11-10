import 'dart:async';
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
import 'package:sicklers_warriors/features/community/presentation/pages/community_post_detail_page.dart';
import 'package:sicklers_warriors/features/community/presentation/pages/forum_notifications_page.dart';

const _token = 'test-access';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

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
  String categorySlug = 'emotional-support',
  bool isPinned = false,
  bool isLocked = false,
  bool isEdited = false,
  bool canModerate = false,
}) => {
  'id': id,
  'uid': uid,
  'author': {'uid': 'u-1', 'display_name': 'Ama'},
  'title': title,
  'content': content,
  'category': category,
  'category_slug': categorySlug,
  'forum_category': {
    'uid': 'cat-1',
    'slug': categorySlug,
    'name': categorySlug == 'emotional-support'
        ? 'Emotional Support'
        : categorySlug,
    'description': '',
    'legacy_code': category,
    'is_active': true,
    'sort_order': 10,
    'post_count': 0,
  },
  'status': status,
  'is_pinned': isPinned,
  'is_locked': isLocked,
  'is_edited': isEdited,
  'can_moderate': canModerate,
  'author_role': 'Patient',
  'last_activity_at': '2026-09-18T08:00:00Z',
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
  'author_role': 'Patient',
  'parent_id': null,
  'depth': 1,
  'is_edited': false,
  'is_deleted': false,
  'reply_count': 0,
  'created_at': '2026-09-18T09:00:00Z',
};

Map<String, dynamic> _forumCategoryJson({
  String slug = 'emotional-support',
  String name = 'Emotional Support',
  int postCount = 0,
}) => {
  'uid': 'cat-$slug',
  'slug': slug,
  'name': name,
  'description': 'A kind place to be heard.',
  'legacy_code': 'SUPPORT',
  'is_active': true,
  'sort_order': 10,
  'post_count': postCount,
};

Map<String, dynamic> _notificationJson({
  int id = 41,
  String status = 'PENDING',
  String postUid = 'post-1',
}) => {
  'id': id,
  'type': 'COMMUNITY',
  'priority': 'NORMAL',
  'channel': 'IN_APP',
  'title': 'New reply to your post',
  'body': 'Open the community forum to read the latest activity.',
  'data': {
    'route': 'community',
    'post_uid': postUid,
    'comment_id': 7,
    'category_slug': 'emotional-support',
  },
  'related_resource_type': 'community_post',
  'related_resource_id': postUid,
  'status': status,
  'read_at': null,
  'sent_at': null,
  'created_at': '2026-09-18T09:00:00Z',
};

Map<String, dynamic> _messageJson({
  String uid = 'msg-1',
  String content = 'How are you feeling?',
  bool isMine = false,
  bool deleted = false,
}) => {
  'uid': uid,
  'conversation_uid': 'conv-1',
  'sender': {
    'uid': isMine ? 'me' : 'doc-1',
    'display_name': isMine ? 'Me' : 'Dr. Mensah',
  },
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
            'results': [_postJson(reactionCount: 3, reacted: true)],
          },
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
        return _json({
          'data': {'id': 9, 'status': 'OPEN'},
        }, 201);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      await repo.createPost(
        access: _token,
        content: 'Hello',
        category: 'SUPPORT',
      );
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
              'results': [_commentJson()],
            },
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
                  {
                    'user': {'uid': 'doc-1', 'display_name': 'Dr. Mensah'},
                    'role_in_chat': 'DOCTOR',
                    'status': 'ACTIVE',
                  },
                  {
                    'user': {'uid': 'me', 'display_name': 'Me'},
                    'role_in_chat': 'PATIENT',
                    'status': 'ACTIVE',
                  },
                ],
                'unread_count': 2,
                'last_message_at': '2026-09-18T10:00:00Z',
              },
            ],
          },
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
              'results': [_postJson(reactionCount: 0)],
            },
          });
        }
        if (request.url.path == '/api/community/posts/post-1/reactions/') {
          return _json({
            'data': {'uid': 'post-1', 'reaction_count': 1, 'reacted': true},
          });
        }
        return http.Response('not found', 404);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityFeedView(accessToken: _token, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hello warriors'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();
      expect(find.textContaining('Support 1'), findsOneWidget);
    });

    testWidgets('create post publishes via the repository', (tester) async {
      var posted = false;
      final client = MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/community/categories/') {
          return _json({
            'data': {
              'results': [_forumCategoryJson()],
            },
          });
        }
        posted = true;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['content'], 'New support post');
        expect(body['category_slug'], 'emotional-support');
        return _json({'data': _postJson(content: 'New support post')}, 201);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityCreatePostView(accessToken: _token, repository: repo),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, AppStrings.postContent),
        'New support post',
      );
      await tester.tap(find.text(AppStrings.publishPost));
      await tester.pumpAndSettle();
      expect(posted, isTrue);
    });
  });

  group('Community forum extension repository', () {
    test('categories + paginated feeds use server slugs and filters', () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}?${request.url.query}');
        if (request.url.path == '/api/community/categories/') {
          return _json({
            'data': {
              'results': [_forumCategoryJson(postCount: 3)],
            },
          });
        }
        return _json({
          'data': {
            'count': 1,
            'next': null,
            'previous': null,
            'results': [_postJson(isPinned: true, isLocked: true)],
          },
        });
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      final categories = await repo.listCategories(access: _token);
      expect(categories.single.name, 'Emotional Support');
      expect(categories.single.postCount, 3);
      final page = await repo.listPostsPage(
        access: _token,
        category: 'emotional-support',
        search: 'pain',
        sort: 'popular',
        page: 2,
        pageSize: 10,
      );
      expect(page.posts.single.isPinned, isTrue);
      expect(page.posts.single.isLocked, isTrue);
      expect(page.hasMore, isFalse);
      expect(calls, [
        'GET /api/community/categories/?',
        'GET /api/community/posts/?category=emotional-support&search=pain&sort=popular&page=2&page_size=10',
      ]);
    });

    test(
      'setPostFlags + comment edit/delete use moderator and author paths',
      () async {
        final calls = <String>[];
        final client = MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/pin/')) {
            expect(jsonDecode(request.body)['is_pinned'], isTrue);
            return _json({'data': _postJson(isPinned: true)});
          }
          if (request.url.path.endsWith('/lock/')) {
            expect(jsonDecode(request.body)['is_locked'], isTrue);
            return _json({'data': _postJson(isLocked: true)});
          }
          if (request.method == 'PATCH') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['content'], 'Edited reply');
            return _json({'data': _commentJson()});
          }
          return http.Response('', 204);
        });
        final repo = CommunityRepository(tokenStore: store, client: client);
        await repo.setPostFlags(access: _token, uid: 'post-1', isPinned: true);
        await repo.setPostFlags(access: _token, uid: 'post-1', isLocked: true);
        await repo.updateComment(
          access: _token,
          uid: 'post-1',
          commentId: 7,
          content: 'Edited reply',
        );
        await repo.deleteComment(access: _token, uid: 'post-1', commentId: 7);
        expect(calls, [
          'POST /api/community/posts/post-1/pin/',
          'POST /api/community/posts/post-1/lock/',
          'PATCH /api/community/posts/post-1/comments/7/',
          'DELETE /api/community/posts/post-1/comments/7/',
        ]);
      },
    );

    test('forum notifications are scoped to the community endpoints', () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/api/community/notifications/unread-count/') {
          return _json({
            'data': {'unread': 2},
          });
        }
        if (request.url.path.endsWith('/read-all/')) {
          return _json({
            'data': {'updated': 2},
          });
        }
        if (request.url.path.endsWith('/read/')) {
          return _json({'data': _notificationJson(status: 'READ')});
        }
        return _json({
          'data': {
            'count': 2,
            'next': null,
            'results': [_notificationJson(), _notificationJson(id: 42)],
          },
        });
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      final items = await repo.listForumNotifications(access: _token);
      expect(items, hasLength(2));
      expect(items.first.isUnread, isTrue);
      expect(items.first.data['post_uid'], 'post-1');
      expect(await repo.forumUnreadCount(access: _token), 2);
      final read = await repo.markForumNotificationRead(access: _token, id: 41);
      expect(read.isUnread, isFalse);
      expect(await repo.markAllForumNotificationsRead(access: _token), 2);
      expect(calls, [
        'GET /api/community/notifications/',
        'GET /api/community/notifications/unread-count/',
        'POST /api/community/notifications/41/read/',
        'POST /api/community/notifications/read-all/',
      ]);
    });
  });

  group('Community forum extension widgets', () {
    testWidgets('feed uses API categories and filters by server slug', (
      tester,
    ) async {
      final calls = <String>[];
      final client = MockClient((request) async {
        if (request.url.path == '/api/community/categories/') {
          return _json({
            'data': {
              'results': [
                _forumCategoryJson(
                  slug: 'pain-and-crises',
                  name: 'Pain & Crises',
                ),
              ],
            },
          });
        }
        if (request.url.path == '/api/community/posts/') {
          calls.add(request.url.query);
          return _json({
            'data': {
              'count': 1,
              'next': null,
              'results': [_postJson()],
            },
          });
        }
        if (request.url.path.endsWith('/unread-count/')) {
          return _json({
            'data': {'unread': 2},
          });
        }
        return http.Response('not found', 404);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityFeedView(accessToken: _token, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pain & Crises'), findsOneWidget);
      expect(find.textContaining('· Emotional Support'), findsOneWidget);
      await tester.tap(find.text('Pain & Crises'));
      await tester.pumpAndSettle();
      expect(calls.last, 'category=pain-and-crises&page_size=10');
    });

    testWidgets('feed sends the search term to the server', (tester) async {
      final queries = <String>[];
      final client = MockClient((request) async {
        if (request.url.path == '/api/community/categories/') {
          return _json({
            'data': {
              'results': [_forumCategoryJson()],
            },
          });
        }
        if (request.url.path == '/api/community/posts/') {
          queries.add(request.url.query);
          return _json({
            'data': {
              'count': 1,
              'next': null,
              'results': [_postJson()],
            },
          });
        }
        if (request.url.path.endsWith('/unread-count/')) {
          return _json({
            'data': {'unread': 0},
          });
        }
        return http.Response('not found', 404);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityFeedView(accessToken: _token, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'pain');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(queries.last, contains('search=pain'));
    });

    testWidgets('feed shows a loading state before the first response', (
      tester,
    ) async {
      final completer = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.url.path == '/api/community/posts/') {
          return completer.future;
        }
        if (request.url.path == '/api/community/categories/') {
          return _json({
            'data': {'results': <Object>[]},
          });
        }
        if (request.url.path.endsWith('/unread-count/')) {
          return _json({
            'data': {'unread': 0},
          });
        }
        return http.Response('not found', 404);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityFeedView(accessToken: _token, repository: repo),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      completer.complete(
        _json({
          'data': {'count': 0, 'next': null, 'results': <Object>[]},
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.noPosts), findsOneWidget);
    });

    testWidgets('empty feed renders the empty state', (tester) async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/community/categories/') {
          return _json({
            'data': {'results': <Object>[]},
          });
        }
        if (request.url.path == '/api/community/posts/') {
          return _json({
            'data': {'count': 0, 'next': null, 'results': <Object>[]},
          });
        }
        if (request.url.path.endsWith('/unread-count/')) {
          return _json({
            'data': {'unread': 0},
          });
        }
        return http.Response('not found', 404);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityFeedView(accessToken: _token, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.noPosts), findsOneWidget);
    });

    testWidgets('feed surfaces an error state with retry', (tester) async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/community/posts/') {
          return _json({
            'error': {'message': 'Server error'},
          }, 500);
        }
        if (request.url.path == '/api/community/categories/') {
          return _json({
            'data': {'results': <Object>[]},
          });
        }
        if (request.url.path.endsWith('/unread-count/')) {
          return _json({
            'data': {'unread': 0},
          });
        }
        return http.Response('not found', 404);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityFeedView(accessToken: _token, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.communityLoadFailed), findsOneWidget);
      expect(find.text(AppStrings.retry), findsWidgets);
    });

    testWidgets('post detail renders threads and sends a parent reply', (
      tester,
    ) async {
      Map<String, dynamic>? postedBody;
      final client = MockClient((request) async {
        if (request.url.path == '/api/community/posts/post-1/') {
          return _json({'data': _postJson()});
        }
        if (request.url.path == '/api/community/categories/') {
          return _json({
            'data': {
              'results': [_forumCategoryJson()],
            },
          });
        }
        if (request.url.path == '/api/community/posts/post-1/comments/' &&
            request.method == 'GET') {
          return _json({
            'data': {
              'count': 2,
              'next': null,
              'results': [
                _commentJson(),
                {
                  ..._commentJson(),
                  'id': 8,
                  'content': 'A threaded reply',
                  'parent_id': 7,
                  'depth': 2,
                  'reply_count': 0,
                  'author': {'uid': 'u-3', 'display_name': 'Dr. Mensah'},
                },
              ],
            },
          });
        }
        if (request.url.path == '/api/community/posts/post-1/comments/' &&
            request.method == 'POST') {
          postedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'data': _commentJson()}, 201);
        }
        return http.Response('not found', 404);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityPostDetailView(
            accessToken: _token,
            repository: repo,
            postUid: 'post-1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A threaded reply'), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.reply));
      await tester.pumpAndSettle();
      expect(find.textContaining(AppStrings.replyingTo), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'My reply');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(postedBody?['parent_id'], 7);
      expect(postedBody?['content'], 'My reply');
    });

    testWidgets('forum activity page lists and marks all read', (tester) async {
      var readAll = false;
      final client = MockClient((request) async {
        if (request.url.path == '/api/community/notifications/' &&
            request.method == 'GET') {
          return _json({
            'data': {
              'count': 1,
              'next': null,
              'results': [_notificationJson()],
            },
          });
        }
        if (request.url.path.endsWith('/read-all/')) {
          readAll = true;
          return _json({
            'data': {'updated': 1},
          });
        }
        return http.Response('not found', 404);
      });
      final repo = CommunityRepository(tokenStore: store, client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: ForumNotificationsView(accessToken: _token, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('New reply to your post'), findsOneWidget);
      await tester.tap(find.text(AppStrings.markAllRead));
      await tester.pumpAndSettle();
      expect(readAll, isTrue);
    });

    testWidgets(
      'opening a notification marks it read and opens the discussion',
      (tester) async {
        var markedRead = false;
        final client = MockClient((request) async {
          if (request.url.path == '/api/community/notifications/' &&
              request.method == 'GET') {
            return _json({
              'data': {
                'count': 1,
                'next': null,
                'results': [_notificationJson()],
              },
            });
          }
          if (request.url.path == '/api/community/notifications/41/read/') {
            markedRead = true;
            return _json({'data': _notificationJson(status: 'READ')});
          }
          if (request.url.path == '/api/community/posts/post-1/') {
            return _json({'data': _postJson()});
          }
          if (request.url.path == '/api/community/posts/post-1/comments/') {
            return _json({
              'data': {'count': 0, 'next': null, 'results': <Object>[]},
            });
          }
          if (request.url.path == '/api/community/categories/') {
            return _json({
              'data': {
                'results': [_forumCategoryJson()],
              },
            });
          }
          return http.Response('not found', 404);
        });
        final repo = CommunityRepository(tokenStore: store, client: client);
        await tester.pumpWidget(
          MaterialApp(
            home: ForumNotificationsView(accessToken: _token, repository: repo),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('New reply to your post'));
        await tester.pumpAndSettle();
        expect(markedRead, isTrue);
        expect(find.text('Stay strong together'), findsOneWidget);
      },
    );
  });

  group('Chat widgets (Stage 4.10)', () {
    testWidgets('thread loads messages and sends a reply', (tester) async {
      var sent = false;
      final client = MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/chat/conversations/conv-1/messages/') {
          return _json({
            'data': {
              'results': [_messageJson(content: 'How are you feeling?')],
            },
          });
        }
        if (request.url.path == '/api/chat/conversations/conv-1/read/') {
          return _json({
            'data': {'updated': 1},
          });
        }
        if (request.method == 'POST') {
          sent = true;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['content'], 'Much better today');
          return _json({
            'data': _messageJson(
              uid: 'msg-2',
              content: 'Much better today',
              isMine: true,
            ),
          }, 201);
        }
        return http.Response('not found', 404);
      });
      final repo = ChatRepository(tokenStore: store, client: client);
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationThreadView(
            accessToken: _token,
            repository: repo,
            conversationUid: 'conv-1',
          ),
        ),
      );
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
