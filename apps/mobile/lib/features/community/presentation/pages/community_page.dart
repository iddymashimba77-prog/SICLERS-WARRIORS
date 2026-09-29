import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../chat/presentation/pages/conversation_list_page.dart';
import '../../../education/presentation/pages/education_page.dart';
import '../../data/community_repository.dart';
import 'community_create_post_page.dart';
import 'community_post_detail_page.dart';

/// Community feed (approved COM-001; FR-COM-001..003).
///
/// Public-to-members content only. Private medical data must never cross into
/// this surface (§14 data boundary); the create screen restates that rule.
class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key, this.authController, this.repository});

  static const String routeName = '/community';

  final AuthController? authController;
  final CommunityRepository? repository;

  @override
  Widget build(BuildContext context) {
    final token = (authController ?? SessionScope.controllerOf(context))
        .accessToken;
    if (token == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(AppStrings.communityFeed)),
        body: const Center(child: Text(AppStrings.notSignedIn)),
      );
    }
    return CommunityFeedView(
      accessToken: token,
      repository:
          repository ?? CommunityRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class CommunityFeedView extends StatefulWidget {
  const CommunityFeedView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final CommunityRepository repository;

  @override
  State<CommunityFeedView> createState() => _CommunityFeedViewState();
}

class _CommunityFeedViewState extends State<CommunityFeedView> {
  List<CommunityPost>? _posts;
  Object? _error;
  bool _loading = true;
  String? _category;
  bool _mine = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await widget.repository.listPosts(
        access: widget.accessToken,
        category: _category,
        mine: _mine,
      );
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _react(CommunityPost post) async {
    try {
      final result = await widget.repository.toggleReaction(
        access: widget.accessToken,
        uid: post.uid,
        on: !post.reacted,
      );
      if (!mounted) return;
      setState(() {
        _posts = [
          for (final p in _posts ?? const <CommunityPost>[])
            if (p.uid == post.uid)
              CommunityPost(
                id: p.id,
                uid: p.uid,
                author: p.author,
                title: p.title,
                content: p.content,
                category: p.category,
                status: p.status,
                reactionCount: (result['reaction_count'] as num?)?.toInt() ?? p.reactionCount,
                commentCount: p.commentCount,
                reacted: (result['reacted'] as bool?) ?? !p.reacted,
                isAuthor: p.isAuthor,
                createdAt: p.createdAt,
              )
            else
              p,
        ];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.communityLoadFailed)),
      );
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityCreatePostView(
          accessToken: widget.accessToken,
          repository: widget.repository,
        ),
      ),
    );
    if (created == true) _load();
  }

  Future<void> _openDetail(CommunityPost post) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityPostDetailView(
          accessToken: widget.accessToken,
          repository: widget.repository,
          postUid: post.uid,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.communityFeed),
        actions: [
          IconButton(
            tooltip: AppStrings.myPosts,
            icon: Icon(_mine ? Icons.person : Icons.person_outline),
            onPressed: () {
              setState(() => _mine = !_mine);
              _load();
            },
          ),
          IconButton(
            tooltip: AppStrings.messages,
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.pushNamed(context, ConversationListPage.routeName),
          ),
          IconButton(
            tooltip: AppStrings.education,
            icon: const Icon(Icons.school_outlined),
            onPressed: () => Navigator.pushNamed(context, EducationPage.routeName),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'new-post',
        onPressed: _openCreate,
        tooltip: AppStrings.createPost,
        child: const Icon(Icons.edit_outlined),
      ),
      body: Column(
        children: [
          _CategoryBar(
            selected: _category,
            onSelected: (value) {
              setState(() => _category = value);
              _load();
            },
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorRetryView(message: AppStrings.communityLoadFailed, onRetry: _load);
    }
    final posts = _posts ?? const <CommunityPost>[];
    if (posts.isEmpty) {
      return const EmptyStateView(
        message: AppStrings.noPosts,
        icon: Icons.forum_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: posts.length,
        itemBuilder: (_, i) => _PostCard(
          post: posts[i],
          onTap: () => _openDetail(posts[i]),
          onReact: () => _react(posts[i]),
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text(AppStrings.allPosts),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final category in communityCategories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(category),
                selected: selected == category,
                onSelected: (_) => onSelected(category),
              ),
            ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.onTap, required this.onReact});

  final CommunityPost post;
  final VoidCallback onTap;
  final VoidCallback onReact;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    child: Text(post.author.displayName.characters.first.toUpperCase()),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${post.author.displayName} · ${post.category}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (!post.isPublished)
                    Chip(
                      label: const Text(AppStrings.underReview),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (post.title.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(post.title, style: Theme.of(context).textTheme.titleMedium),
              ],
              const SizedBox(height: 6),
              Text(post.content, maxLines: 4, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onReact,
                    icon: Icon(
                      post.reacted ? Icons.favorite : Icons.favorite_border,
                      color: post.reacted ? AppColors.primary : null,
                    ),
                    label: Text('${AppStrings.likePost} ${post.reactionCount}'),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.mode_comment_outlined, size: 16),
                  const SizedBox(width: 4),
                  Text('${post.commentCount}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
