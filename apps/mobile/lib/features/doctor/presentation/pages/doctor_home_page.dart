import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../../../shared/widgets/dashboard_widgets.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/data/token_store.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../chat/data/chat_repository.dart';
import '../../../chat/presentation/pages/conversation_list_page.dart';
import '../../../notifications/data/notifications_repository.dart';
import '../../../notifications/presentation/pages/notifications_page.dart';
import '../../../../shared/widgets/signed_out_gate.dart';

/// Doctor home (FRONTEND-3): a dedicated experience, not a copy of the patient
/// dashboard. Shows the doctor's real authorized surfaces (conversations,
/// notifications) and honest empty states where the backend owns the data
/// (appointments, patient records, tasks).
class DoctorHomePage extends StatelessWidget {
  const DoctorHomePage({super.key, this.authController, this.repository});

  static const String routeName = '/doctor-home';

  final AuthController? authController;
  final DoctorHomeRepository? repository;

  @override
  Widget build(BuildContext context) {
    final session = authController ?? SessionScope.controllerOf(context);
    final token = session.accessToken;
    if (token == null) {
      return const SignedOutGate();
    }
    final repo = repository ??
        DoctorHomeRepository(tokenStore: EphemeralTokenStore());
    return Scaffold(
      appBar: AppTopBar(
        title: AppStrings.doctorHome,
        avatarName: session.displayName,
        unreadCount: 0,
      ),
      body: SafeArea(
        child: DoctorHomeView(accessToken: token, repository: repo),
      ),
    );
  }
}

class DoctorHomeRepository {
  DoctorHomeRepository({TokenStore? tokenStore})
      : chat = ChatRepository(tokenStore: tokenStore ?? EphemeralTokenStore()),
        notifications = NotificationsRepository(
            tokenStore: tokenStore ?? EphemeralTokenStore());

  final ChatRepository chat;
  final NotificationsRepository notifications;
}

class _DoctorHomeData {
  const _DoctorHomeData({
    this.unread = 0,
    required this.conversations,
  });

  final int unread;
  final List<Conversation> conversations;
}

class DoctorHomeView extends StatefulWidget {
  const DoctorHomeView({
    super.key,
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final DoctorHomeRepository repository;

  @override
  State<DoctorHomeView> createState() => _DoctorHomeViewState();
}

class _DoctorHomeViewState extends State<DoctorHomeView> {
  _DoctorHomeData? _data;
  Object? _error;
  bool _loading = true;

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
      final results = await Future.wait<Object>([
        widget.repository.notifications.unreadCount(access: widget.accessToken),
        widget.repository.chat.listConversations(access: widget.accessToken),
      ]);
      if (!mounted) return;
      setState(() {
        _data = _DoctorHomeData(
          unread: results[0] as int,
          conversations: results[1] as List<Conversation>,
        );
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SkeletonListView(rows: 5);
    if (_error != null) {
      return ErrorRetryView(message: AppStrings.threadLoadFailed, onRetry: _load);
    }
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'Signed in as a verified healthcare professional on this backend '
            'session.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          StatGrid(
            children: [
              StatCard(
                label: AppStrings.todayAppointments,
                value: '0',
                icon: Icons.event_available_outlined,
              ),
              StatCard(
                label: AppStrings.pendingRequests,
                value: '0',
                icon: Icons.outbox_outlined,
              ),
              StatCard(
                label: AppStrings.patientCommunication,
                value: '${data.conversations.length}',
                icon: Icons.chat_bubble_outline,
              ),
              StatCard(
                label: AppStrings.inboxWithUnread,
                value: '${data.unread}',
                icon: Icons.notifications_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            title: AppStrings.patientCommunication,
            actionLabel: AppStrings.viewAll,
            onAction: () => Navigator.pushNamed(
              context,
              ConversationListPage.routeName,
            ),
          ),
          if (data.conversations.isEmpty)
            const EmptyStateView(
              message: AppStrings.noConversations,
              icon: Icons.chat_bubble_outline,
            )
          else
            for (final c in data.conversations.take(4))
              AppCard.action(
                onTap: () => Navigator.pushNamed(
                  context,
                  ConversationListPage.routeName,
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(c.displayTitle),
                  subtitle: Text(
                    c.unreadCount > 0
                        ? '${c.unreadCount} unread'
                        : AppStrings.sharedUnderConsent,
                  ),
                ),
              ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: AppStrings.todayAppointments),
          const EmptyStateView(
            message: AppStrings.noAppointmentsToday,
            icon: Icons.event_busy_outlined,
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: AppStrings.pendingRequests),
          const EmptyStateView(
            message: AppStrings.noPendingRequests,
            icon: Icons.outbox_outlined,
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: AppStrings.recentPatientActivity),
          const EmptyStateView(
            message: AppStrings.noAuthorizedActivity,
            icon: Icons.lock_outline,
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: AppStrings.doctorTasks),
          const EmptyStateView(
            message: AppStrings.noTasks,
            icon: Icons.task_alt_outlined,
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text(AppStrings.inboxWithUnread),
              subtitle: Text('${data.unread} ${AppStrings.unread.toLowerCase()}'),
              trailing: IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => Navigator.pushNamed(
                  context,
                  NotificationsPage.routeName,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}