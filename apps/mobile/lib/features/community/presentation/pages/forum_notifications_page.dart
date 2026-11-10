import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../notifications/data/notifications_repository.dart'
    show AppNotification;
import '../../data/community_repository.dart';
import 'community_post_detail_page.dart';

/// Recipient-scoped forum activity (comments, replies, reactions).
///
/// Reuses the generic notification rows with a `COMMUNITY` type and a forum
/// metadata payload, but only exposes the community-scoped API endpoints. Admin
/// accounts are denied by the backend and never reach this member surface.
class ForumNotificationsPage extends StatelessWidget {
  const ForumNotificationsPage({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  static const String routeName = '/community/notifications';

  final String accessToken;
  final CommunityRepository repository;

  @override
  Widget build(BuildContext context) {
    return ForumNotificationsView(
      accessToken: accessToken,
      repository: repository,
    );
  }
}

class ForumNotificationsView extends StatefulWidget {
  const ForumNotificationsView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final CommunityRepository repository;

  @override
  State<ForumNotificationsView> createState() => _ForumNotificationsViewState();
}

class _ForumNotificationsViewState extends State<ForumNotificationsView> {
  List<AppNotification>? _items;
  Object? _error;
  bool _loading = true;
  bool _markingAll = false;

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
      final items = await widget.repository.listForumNotifications(
        access: widget.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _open(AppNotification item) async {
    try {
      if (item.isUnread) {
        await widget.repository.markForumNotificationRead(
          access: widget.accessToken,
          id: item.id,
        );
      }
    } catch (_) {
      _notify(AppStrings.notificationsReadFailed);
      return;
    }
    final postUid = item.data['post_uid'];
    if (postUid is String && postUid.isNotEmpty && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CommunityPostDetailView(
            accessToken: widget.accessToken,
            repository: widget.repository,
            postUid: postUid,
          ),
        ),
      );
    }
    if (mounted) await _load();
  }

  Future<void> _readAll() async {
    setState(() => _markingAll = true);
    try {
      await widget.repository.markAllForumNotificationsRead(
        access: widget.accessToken,
      );
      if (!mounted) return;
      _notify(AppStrings.notificationsAllRead);
      await _load();
    } catch (_) {
      _notify(AppStrings.notificationsReadFailed);
    } finally {
      if (mounted) setState(() => _markingAll = false);
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
    final items = _items ?? const <AppNotification>[];
    final hasUnread = items.any((n) => n.isUnread);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.forumNotifications),
        actions: [
          if (hasUnread)
            TextButton.icon(
              onPressed: _markingAll ? null : _readAll,
              icon: const Icon(Icons.done_all, size: 18),
              label: Text(AppStrings.markAllRead),
            ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
          ? ErrorRetryView(
              message: AppStrings.forumNotificationsLoadFailed,
              onRetry: _load,
            )
          : items.isEmpty
          ? EmptyStateView(
              message: AppStrings.forumNoNotifications,
              icon: Icons.forum_outlined,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final item = items[i];
                  return Card(
                    child: ListTile(
                      onTap: () => _open(item),
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.12,
                            ),
                            child: const Icon(
                              Icons.forum_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                          if (item.isUnread)
                            Positioned(
                              right: -1,
                              top: -1,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: AppColors.emergency,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        item.title,
                        style: TextStyle(
                          fontWeight: item.isUnread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(item.body),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
