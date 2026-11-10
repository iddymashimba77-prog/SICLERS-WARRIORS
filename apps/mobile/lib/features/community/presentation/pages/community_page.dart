import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/banners/page_banner_catalog.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/role_gate.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../chat/presentation/pages/conversation_list_page.dart';
import '../../../education/presentation/pages/education_page.dart';
import '../../data/community_repository.dart';
import 'community_create_post_page.dart';
import 'community_post_detail_page.dart';
import 'forum_notifications_page.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../shared/widgets/signed_out_gate.dart';

/// Community forum feed (approved COM-001; FR-COM-001..003).
///
/// Member-only content. Admin/SUPER_ADMIN accounts are denied by the backend and
/// shown a routing-level restricted state. Private medical data never crosses
/// into this surface (§14 data boundary).
class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key, this.authController, this.repository});

  static const String routeName = '/community';

  final AuthController? authController;
  final CommunityRepository? repository;

  @override
  Widget build(BuildContext context) {
    final controller = authController ?? SessionScope.controllerOf(context);
    final token = controller.accessToken;
    if (token == null) {
      return const SignedOutGate();
    }
    if (AppRoles.isAdminRole(controller.roles)) {
      return const ForumRestrictedView();
    }
    return CommunityFeedView(
      accessToken: token,
      repository:
          repository ?? CommunityRepository(tokenStore: EphemeralTokenStore()),
    );
  }
}

class ForumRestrictedView extends StatelessWidget {
  const ForumRestrictedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.communityForum)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                AppStrings.forumMembersOnly,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.forumAdminsRestricted,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
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
  final _searchController = TextEditingController();
  List<CommunityPost>? _posts;
  List<ForumCategory> _categories = const [];
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  int _unread = 0;
  String? _category;
  bool _mine = false;
  String _search = '';
  String _sort = 'latest';

  @override
  void initState() {
    super.initState();
    _load();
    _loadCategories();
    _loadBadge();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (append) {
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    }
    try {
      final page = await widget.repository.listPostsPage(
        access: widget.accessToken,
        category: _category,
        mine: _mine,
        search: _search,
        sort: _sort,
        page: append ? _page + 1 : 1,
        pageSize: 10,
      );
      if (!mounted) return;
      setState(() {
        _posts = append ? [...?_posts, ...page.posts] : page.posts;
        _page = page.page;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await widget.repository.listCategories(
        access: widget.accessToken,
      );
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (_) {
      // The feed remains usable if the category call degrades.
    }
  }

  Future<void> _loadBadge() async {
    try {
      final unread = await widget.repository.forumUnreadCount(
        access: widget.accessToken,
      );
      if (!mounted) return;
      setState(() => _unread = unread);
    } catch (_) {
      // Badge is best-effort; the inbox itself surfaces real errors.
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
              p.copyWith(
                reactionCount:
                    (result['reaction_count'] as num?)?.toInt() ??
                    p.reactionCount,
                reacted: (result['reacted'] as bool?) ?? !p.reacted,
              )
            else
              p,
        ];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.communityLoadFailed)));
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
    _loadBadge();
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForumNotificationsPage(
          accessToken: widget.accessToken,
          repository: widget.repository,
        ),
      ),
    );
    _loadBadge();
  }

  void _applySearch(String value) {
    setState(() => _search = value.trim());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.communityForum),
        actions: [
          IconButton(
            tooltip: AppStrings.forumNotifications,
            icon: Badge(
              isLabelVisible: _unread > 0,
              label: Text(_unread > 99 ? '99+' : '$_unread'),
              child: const Icon(Icons.notifications_none),
            ),
            onPressed: _openNotifications,
          ),
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
            onPressed: () =>
                Navigator.pushNamed(context, ConversationListPage.routeName),
          ),
          IconButton(
            tooltip: AppStrings.education,
            icon: const Icon(Icons.school_outlined),
            onPressed: () =>
                Navigator.pushNamed(context, EducationPage.routeName),
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
          const PageBanner(
            page: BannerPage.community,
            margin: EdgeInsets.fromLTRB(12, 12, 12, 0),
          ),
          const _MedicalNotice(),
          _CategoryBar(
            categories: _categories,
            selected: _category,
            onSelected: (value) {
              setState(() => _category = value);
              _load();
            },
          ),
          _SearchSortBar(
            controller: _searchController,
            sort: _sort,
            onSearch: _applySearch,
            onClear: () {
              _searchController.clear();
              _applySearch('');
            },
            onSort: (value) {
              setState(() => _sort = value);
              _load();
            },
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// Keeps loading/error/empty states scrollable on short screens where the
  /// banner + safety notice + filters leave little vertical room.
  Widget _scrollableState(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _scrollableState(const LoadingView());
    if (_error != null) {
      return _scrollableState(
        ErrorRetryView(message: AppStrings.communityLoadFailed, onRetry: _load),
      );
    }
    final posts = _posts ?? const <CommunityPost>[];
    if (posts.isEmpty) {
      return _scrollableState(
        EmptyStateView(message: AppStrings.noPosts, icon: Icons.forum_outlined),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: posts.length + (_hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= posts.length) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: () => _load(append: true),
                        child: Text(AppStrings.loadMore),
                      ),
              ),
            );
          }
          final post = posts[i];
          return _PostCard(
            post: post,
            onTap: () => _openDetail(post),
            onReact: () => _react(post),
          );
        },
      ),
    );
  }
}

class _MedicalNotice extends StatelessWidget {
  const _MedicalNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              AppStrings.communityMedicalNotice,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<ForumCategory> categories;
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
              label: Text(AppStrings.allPosts),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(category.name),
                selected: selected == category.slug,
                onSelected: (_) => onSelected(category.slug),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchSortBar extends StatelessWidget {
  const _SearchSortBar({
    required this.controller,
    required this.sort,
    required this.onSearch,
    required this.onClear,
    required this.onSort,
  });

  final TextEditingController controller;
  final String sort;
  final ValueChanged<String> onSearch;
  final VoidCallback onClear;
  final ValueChanged<String> onSort;

  String get _sortLabel => switch (sort) {
    'newest' => AppStrings.sortNewest,
    'oldest' => AppStrings.sortOldest,
    'popular' => AppStrings.sortPopular,
    _ => AppStrings.sortLatest,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: AppStrings.searchPosts,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: onClear,
                      ),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: onSearch,
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: _sortLabel,
            initialValue: sort,
            onSelected: onSort,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'latest',
                child: Text(AppStrings.sortLatest),
              ),
              PopupMenuItem(
                value: 'newest',
                child: Text(AppStrings.sortNewest),
              ),
              PopupMenuItem(
                value: 'oldest',
                child: Text(AppStrings.sortOldest),
              ),
              PopupMenuItem(
                value: 'popular',
                child: Text(AppStrings.sortPopular),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Icon(Icons.sort, semanticLabel: _sortLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.onTap,
    required this.onReact,
  });

  final CommunityPost post;
  final VoidCallback onTap;
  final VoidCallback onReact;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppShapes.tile,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    child: Text(
                      post.author.displayName.characters.first.toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${post.author.displayName} · ${post.categoryLabel}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (post.isPinned)
                    Tooltip(
                      message: AppStrings.pinned,
                      child: const Icon(
                        Icons.push_pin,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                  if (post.isLocked)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Tooltip(
                        message: AppStrings.locked,
                        child: const Icon(Icons.lock_outline, size: 18),
                      ),
                    ),
                  if (!post.isPublished)
                    Chip(
                      label: Text(AppStrings.underReview),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (post.title.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  post.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
              const SizedBox(height: 6),
              Text(post.content, maxLines: 4, overflow: TextOverflow.ellipsis),
              if (post.isEdited) ...[
                const SizedBox(height: 4),
                Text(
                  AppStrings.edited,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
                  const Icon(Icons.mode_comment_outlined, size: 16),
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
