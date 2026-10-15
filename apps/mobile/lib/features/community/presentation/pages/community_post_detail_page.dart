import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/community_repository.dart';

/// Post detail with comments (approved COM-002/COM-005; FR-COM-002/003).
///
/// Reporting sends spoiler-safe metadata only (target type/id + reason); the
/// backend stores no copy of the reported body.
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
  State<CommunityPostDetailView> createState() => _CommunityPostDetailViewState();
}

class _CommunityPostDetailViewState extends State<CommunityPostDetailView> {
  final _commentController = TextEditingController();
  CommunityPost? _post;
  List<CommunityComment> _comments = const [];
  Object? _error;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
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
        _post = CommunityPost(
          id: post.id,
          uid: post.uid,
          author: post.author,
          title: post.title,
          content: post.content,
          category: post.category,
          status: post.status,
          reactionCount: (result['reaction_count'] as num?)?.toInt() ?? post.reactionCount,
          commentCount: post.commentCount,
          reacted: (result['reacted'] as bool?) ?? !post.reacted,
          isAuthor: post.isAuthor,
          createdAt: post.createdAt,
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
      );
      _commentController.clear();
      if (!mounted) return;
      setState(() => _sending = false);
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppStrings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppStrings.deletePost)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deletePost(access: widget.accessToken, uid: widget.postUid);
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
    final edited = await showDialog<({String title, String content, String category})>(
      context: context,
      builder: (ctx) => _EditPostDialog(
        initialTitle: post.title,
        initialContent: post.content,
        initialCategory: post.category,
      ),
    );
    if (edited == null) return;
    try {
      await widget.repository.updatePost(
        access: widget.accessToken,
        uid: post.uid,
        content: edited.content,
        title: edited.title,
        category: edited.category,
      );
      if (!mounted) return;
      _notify(AppStrings.postUpdated);
      _load();
    } catch (_) {
      _notify(AppStrings.postEditFailed);
    }
  }

  Future<void> _report({required String targetType, required int targetId}) async {
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
      _notify(e.toString().contains('already reported')
          ? AppStrings.reportDuplicate
          : AppStrings.reportFailed);
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.communityFeed),
        actions: [
          if (_post != null && _post!.isAuthor) ...[
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
      return ErrorRetryView(message: AppStrings.communityLoadFailed, onRetry: _load);
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
              Text(
                '${post.author.displayName} · ${post.category}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (post.title.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(post.title, style: Theme.of(context).textTheme.titleLarge),
              ],
              const SizedBox(height: 8),
              Text(post.content),
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
                      onPressed: () => _report(
                        targetType: 'POST',
                        targetId: post.id,
                      ),
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(AppStrings.reportContent),
                    ),
                ],
              ),
              const Divider(height: 32),
              Text(AppStrings.comments, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_comments.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(AppStrings.noComments),
                ),
              for (final comment in _comments) _CommentTile(
                comment: comment,
                onReport: () => _report(targetType: 'COMMENT', targetId: comment.id),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: AppStrings.commentHint,
                      border: OutlineInputBorder(),
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
          ),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.onReport});

  final CommunityComment comment;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(comment.author.displayName, style: Theme.of(context).textTheme.labelLarge),
      subtitle: Text(comment.content),
      trailing: comment.isAuthor
          ? null
          : IconButton(
              tooltip: AppStrings.reportContent,
              icon: const Icon(Icons.flag_outlined, size: 18),
              onPressed: onReport,
            ),
    );
  }
}

class _EditPostDialog extends StatefulWidget {
  const _EditPostDialog({
    required this.initialTitle,
    required this.initialContent,
    required this.initialCategory,
  });

  final String initialTitle;
  final String initialContent;
  final String initialCategory;

  @override
  State<_EditPostDialog> createState() => _EditPostDialogState();
}

class _EditPostDialogState extends State<_EditPostDialog> {
  late final _titleController = TextEditingController(text: widget.initialTitle);
  late final _contentController =
      TextEditingController(text: widget.initialContent);
  late String _category = widget.initialCategory;

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
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: AppStrings.postContent,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: communityCategories.contains(_category)
                  ? _category
                  : 'GENERAL',
              decoration: InputDecoration(
                labelText: AppStrings.postCategory,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in communityCategories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (value) {
                if (value != null) _category = value;
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
            Navigator.pop(
              context,
              (
                title: _titleController.text.trim(),
                content: content,
                category: _category,
              ),
            );
          },
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
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppStrings.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(AppStrings.reportContent),
        ),
      ],
    );
  }
}
