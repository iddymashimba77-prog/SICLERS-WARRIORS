import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/community_repository.dart';

/// Post detail with threaded comments (approved COM-002/COM-005).
///
/// Reporting sends spoiler-safe metadata only (target type/id + reason); the
/// backend stores no copy of the reported body. Deleted comments are rendered as
/// content-free tombstones when replies need them for structure.
class CommunityPostDetailView extends StatefulWidget {
  const CommunityPostDetailView({
    super.key,
    required this.accessToken,
    required this.repository,
    required this.postUid,
  });

  final String accessToken;
  final CommunityRepository repository;
  final String postUid;

  @override
  State<CommunityPostDetailView> createState() =>
      _CommunityPostDetailViewState();
}

class _CommunityPostDetailViewState extends State<CommunityPostDetailView> {
  final _commentController = TextEditingController();
  CommunityPost? _post;
  List<CommunityComment> _comments = const [];
  List<ForumCategory> _categories = const [];
  CommunityComment? _replyTo;
  Object? _error;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCategories();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final post = await widget.repository.getPost(
        access: widget.accessToken,
        uid: widget.postUid,
      );
      final comments = await widget.repository.listComments(
        access: widget.accessToken,
        uid: widget.postUid,
      );
      if (!mounted) return;
      setState(() {
        _post = post;
        _comments = comments;
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

  Future<void> _loadCategories() async {
    try {
      final categories = await widget.repository.listCategories(
        access: widget.accessToken,
      );
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (_) {
      // Editing still works with a fallback label if categories are unavailable.
    }
  }

  Future<void> _react() async {
    final post = _post;
    if (post == null) return;
    try {
      final result = await widget.repository.toggleReaction(
        access: widget.accessToken,
        uid: post.uid,
        on: !post.reacted,
      );
      if (!mounted) return;
      setState(() {
        _post = post.copyWith(
          reactionCount:
              (result['reaction_count'] as num?)?.toInt() ?? post.reactionCount,
          reacted: (result['reacted'] as bool?) ?? !post.reacted,
        );
      });
    } catch (_) {
      _notify(AppStrings.communityLoadFailed);
    }
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.repository.createComment(
        access: widget.accessToken,
        uid: widget.postUid,
        content: text,
        parentId: _replyTo?.id,
      );
      _commentController.clear();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _replyTo = null;
      });
      _notify(AppStrings.commentPosted);
      _load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      _notify(AppStrings.commentFailed);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.deletePost),
        content: Text(AppStrings.deletePostConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.deletePost),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deletePost(
        access: widget.accessToken,
        uid: widget.postUid,
      );
      if (!mounted) return;
      _notify(AppStrings.postDeleted);
      Navigator.pop(context, true);
    } catch (_) {
      _notify(AppStrings.deleteFailed);
    }
  }

  Future<void> _edit() async {
    final post = _post;
    if (post == null || !post.isAuthor) return;
    final categories = _categories.isEmpty
        ? [
            ForumCategory(
              uid: '',
              slug: post.categorySlug,
              name: post.category,
              legacyCode: post.category,
            ),
          ]
        : _categories;
    final edited =
        await showDialog<({String title, String content, String categorySlug})>(
          context: context,
          builder: (ctx) => _EditPostDialog(
            initialTitle: post.title,
            initialContent: post.content,
            initialCategorySlug: post.categorySlug,
            categories: categories,
          ),
        );
    if (edited == null) return;
    try {
      await widget.repository.updatePost(
        access: widget.accessToken,
        uid: post.uid,
        content: edited.content,
        title: edited.title,
        categorySlug: edited.categorySlug,
      );
      if (!mounted) return;
      _notify(AppStrings.postUpdated);
      _load();
    } catch (_) {
      _notify(AppStrings.postEditFailed);
    }
  }

  Future<void> _editComment(CommunityComment comment) async {
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => _EditCommentDialog(initialContent: comment.content),
    );
    if (updated == null || updated.trim().isEmpty) return;
    try {
      await widget.repository.updateComment(
        access: widget.accessToken,
        uid: widget.postUid,
        commentId: comment.id,
        content: updated.trim(),
      );
      if (!mounted) return;
      _notify(AppStrings.commentUpdated);
      _load();
    } catch (_) {
      _notify(AppStrings.commentEditFailed);
    }
  }

  Future<void> _deleteComment(CommunityComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.deleteComment),
        content: Text(AppStrings.deleteCommentConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.deleteComment),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteComment(
        access: widget.accessToken,
        uid: widget.postUid,
        commentId: comment.id,
      );
      if (!mounted) return;
      _notify(AppStrings.commentDeleted);
      if (_replyTo?.id == comment.id) setState(() => _replyTo = null);
      _load();
    } catch (_) {
      _notify(AppStrings.commentDeleteFailed);
    }
  }

  Future<void> _togglePin() async {
    final post = _post;
    if (post == null) return;
    try {
      final updated = await widget.repository.setPostFlags(
        access: widget.accessToken,
        uid: post.uid,
        isPinned: !post.isPinned,
      );
      if (!mounted) return;
      setState(() => _post = updated);
    } catch (_) {
      _notify(AppStrings.forumModerationFailed);
    }
  }

  Future<void> _toggleLock() async {
    final post = _post;
    if (post == null) return;
    try {
      final updated = await widget.repository.setPostFlags(
        access: widget.accessToken,
        uid: post.uid,
        isLocked: !post.isLocked,
      );
      if (!mounted) return;
      setState(() => _post = updated);
    } catch (_) {
      _notify(AppStrings.forumModerationFailed);
    }
  }

  Future<void> _report({
    required String targetType,
    required int targetId,
  }) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => const _ReportDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await widget.repository.reportContent(
        access: widget.accessToken,
        targetType: targetType,
        targetId: targetId,
        reason: reason.trim(),
      );
      _notify(AppStrings.reportSubmitted);
    } catch (e) {
      _notify(
        e.toString().contains('already reported')
            ? AppStrings.reportDuplicate
            : AppStrings.reportFailed,
      );
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.communityForum),
        actions: [
          if (post != null && post.canModerate) ...[
            IconButton(
              tooltip: post.isPinned
                  ? AppStrings.unpinPost
                  : AppStrings.pinPost,
              icon: Icon(
                post.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              onPressed: _togglePin,
            ),
            IconButton(
              tooltip: post.isLocked
                  ? AppStrings.unlockPost
                  : AppStrings.lockPost,
              icon: Icon(post.isLocked ? Icons.lock : Icons.lock_open),
              onPressed: _toggleLock,
            ),
          ],
          if (post != null && post.isAuthor) ...[
            IconButton(
              tooltip: AppStrings.editPost,
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
            IconButton(
              tooltip: AppStrings.deletePost,
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorRetryView(
        message: AppStrings.communityLoadFailed,
        onRetry: _load,
      );
    }
    final post = _post;
    if (post == null) {
      return EmptyStateView(message: AppStrings.noPosts);
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${post.author.displayName} · ${post.authorRole} · ${post.categoryLabel}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (post.isPinned)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.push_pin, size: 14),
                      label: Text(AppStrings.pinned),
                    ),
                  if (post.isLocked)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Tooltip(
                        message: AppStrings.locked,
                        child: const Icon(Icons.lock_outline, size: 18),
                      ),
                    ),
                ],
              ),
              if (post.title.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(post.title, style: Theme.of(context).textTheme.titleLarge),
              ],
              const SizedBox(height: 8),
              Text(post.content),
              if (post.isEdited) ...[
                const SizedBox(height: 6),
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
                    onPressed: _react,
                    icon: Icon(
                      post.reacted ? Icons.favorite : Icons.favorite_border,
                      color: post.reacted ? AppColors.primary : null,
                    ),
                    label: Text('${AppStrings.likePost} ${post.reactionCount}'),
                  ),
                  if (!post.isAuthor)
                    TextButton.icon(
                      onPressed: () =>
                          _report(targetType: 'POST', targetId: post.id),
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(AppStrings.reportContent),
                    ),
                ],
              ),
              const Divider(height: 32),
              Text(
                AppStrings.comments,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_comments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(AppStrings.noComments),
                ),
              for (final comment in _comments)
                _CommentTile(
                  comment: comment,
                  onReport: () =>
                      _report(targetType: 'COMMENT', targetId: comment.id),
                  onReply: comment.isDeleted
                      ? null
                      : () => _startReply(comment),
                  onEdit: comment.isAuthor && !comment.isDeleted
                      ? () => _editComment(comment)
                      : null,
                  onDelete: comment.isAuthor && !comment.isDeleted
                      ? () => _deleteComment(comment)
                      : null,
                ),
            ],
          ),
        ),
        if (post.isLocked)
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                AppStrings.discussionLocked,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        else
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyTo != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${AppStrings.replyingTo} ${_replyTo!.author.displayName}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _replyTo = null),
                          child: Text(AppStrings.cancelReply),
                        ),
                      ],
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          decoration: InputDecoration(
                            hintText: _replyTo == null
                                ? AppStrings.commentHint
                                : AppStrings.writeReply,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _addComment(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sending ? null : _addComment,
                        tooltip: AppStrings.addComment,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _startReply(CommunityComment comment) {
    setState(() => _replyTo = comment);
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.onReport,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
  });

  final CommunityComment comment;
  final VoidCallback onReport;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final indent = (comment.depth - 1).clamp(0, 4) * 16.0;
    final hasMenu = onEdit != null || onDelete != null || !comment.isAuthor;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          '${comment.author.displayName} · ${comment.authorRole}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              comment.isDeleted ? AppStrings.commentRemoved : comment.content,
            ),
            if (comment.isEdited && !comment.isDeleted)
              Text(
                AppStrings.edited,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        trailing: !hasMenu
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'reply':
                      onReply?.call();
                    case 'edit':
                      onEdit?.call();
                    case 'delete':
                      onDelete?.call();
                    case 'report':
                      onReport();
                  }
                },
                itemBuilder: (context) => [
                  if (onReply != null)
                    PopupMenuItem(
                      value: 'reply',
                      child: Text(AppStrings.reply),
                    ),
                  if (onEdit != null)
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(AppStrings.editComment),
                    ),
                  if (onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(AppStrings.deleteComment),
                    ),
                  if (!comment.isAuthor && !comment.isDeleted)
                    PopupMenuItem(
                      value: 'report',
                      child: Text(AppStrings.reportContent),
                    ),
                ],
              ),
      ),
    );
  }
}

class _EditPostDialog extends StatefulWidget {
  const _EditPostDialog({
    required this.initialTitle,
    required this.initialContent,
    required this.initialCategorySlug,
    required this.categories,
  });

  final String initialTitle;
  final String initialContent;
  final String initialCategorySlug;
  final List<ForumCategory> categories;

  @override
  State<_EditPostDialog> createState() => _EditPostDialogState();
}

class _EditPostDialogState extends State<_EditPostDialog> {
  late final _titleController = TextEditingController(
    text: widget.initialTitle,
  );
  late final _contentController = TextEditingController(
    text: widget.initialContent,
  );
  late String _categorySlug =
      widget.categories.any((c) => c.slug == widget.initialCategorySlug)
      ? widget.initialCategorySlug
      : widget.categories.first.slug;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppStrings.editPost),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: AppStrings.postTitle,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: AppStrings.postContent,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _categorySlug,
              decoration: InputDecoration(
                labelText: AppStrings.postCategory,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final category in widget.categories)
                  DropdownMenuItem(
                    value: category.slug,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (value) {
                if (value != null) _categorySlug = value;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppStrings.cancel),
        ),
        FilledButton(
          onPressed: () {
            final content = _contentController.text.trim();
            if (content.isEmpty) return;
            Navigator.pop(context, (
              title: _titleController.text.trim(),
              content: content,
              categorySlug: _categorySlug,
            ));
          },
          child: Text(AppStrings.updatePost),
        ),
      ],
    );
  }
}

class _EditCommentDialog extends StatefulWidget {
  const _EditCommentDialog({required this.initialContent});

  final String initialContent;

  @override
  State<_EditCommentDialog> createState() => _EditCommentDialogState();
}

class _EditCommentDialogState extends State<_EditCommentDialog> {
  late final _controller = TextEditingController(text: widget.initialContent);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppStrings.editComment),
      content: TextField(
        controller: _controller,
        maxLines: 4,
        maxLength: 5000,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppStrings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(AppStrings.updatePost),
        ),
      ],
    );
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppStrings.reportContent),
      content: TextField(
        controller: _controller,
        maxLines: 3,
        maxLength: 2000,
        decoration: InputDecoration(
          labelText: AppStrings.reportReason,
          hintText: AppStrings.reportReasonHint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppStrings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(AppStrings.reportContent),
        ),
      ],
    );
  }
}
