import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../chat/presentation/pages/conversation_list_page.dart';
import '../../../community/presentation/pages/community_page.dart';
import '../../../education/presentation/pages/education_page.dart';
import '../../../notifications/data/notifications_repository.dart';
import '../../../auth/data/token_store.dart';
import '../../../notifications/presentation/pages/notifications_page.dart';
import '../../../../shared/widgets/signed_out_gate.dart';

/// Caregiver home (FRONTEND-3).
///
/// A caregiver never sees a patient's data automatically. Linked patients,
/// health updates and medication reminders appear ONLY when the backend
/// authorizes them; until then this surface shows honest empty states plus the
/// caregiver's own authorized surfaces (community, academy, messages,
/// notifications).
class CaregiverHomePage extends StatelessWidget {
  const CaregiverHomePage({super.key, this.authController, this.repository});

  static const String routeName = '/caregiver-home';

  final AuthController? authController;
  final CaregiverHomeRepository? repository;

  @override
  Widget build(BuildContext context) {
    final session = authController ?? SessionScope.controllerOf(context);
    final token = session.accessToken;
    if (token == null) {
      return const SignedOutGate();
    }
    return Scaffold(
      appBar: AppTopBar(
        title: AppStrings.caregiverHome,
        avatarName: session.displayName,
      ),
      body: SafeArea(
        child: _CaregiverHomeBody(
          accessToken: token,
          repository: repository ?? CaregiverHomeRepository(),
        ),
      ),
    );
  }
}

class CaregiverHomeRepository {
  final NotificationsRepository notifications = NotificationsRepository(
    tokenStore: EphemeralTokenStore(),
  );
}

class _CaregiverHomeBody extends StatefulWidget {
  const _CaregiverHomeBody({
    required this.accessToken,
    required this.repository,
  });

  final String accessToken;
  final CaregiverHomeRepository repository;

  @override
  State<_CaregiverHomeBody> createState() => _CaregiverHomeBodyState();
}

class _CaregiverHomeBodyState extends State<_CaregiverHomeBody> {
  int? _unread;

  @override
  void initState() {
    super.initState();
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    try {
      final unread = await widget.repository.notifications
          .unreadCount(access: widget.accessToken);
      if (!mounted) return;
      setState(() => _unread = unread);
    } catch (_) {
      // Non-critical: leave the badge silent on failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              AppStrings.caregiverOnlyAuthorized,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          AppStrings.linkedPatients.toUpperCase(),
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        EmptyStateView(
          message: AppStrings.noLinkedPatients,
          icon: Icons.people_outline,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          AppStrings.caregiverHealthUpdates.toUpperCase(),
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        EmptyStateView(
          message: AppStrings.noHealthUpdates,
          icon: Icons.health_and_safety_outlined,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          AppStrings.caregiverCommunication.toUpperCase(),
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        _LinkCard(
          icon: Icons.chat_bubble_outline,
          title: AppStrings.messages,
          subtitle: AppStrings.medicationReminderAccess,
          onTap: () =>
              Navigator.pushNamed(context, ConversationListPage.routeName),
        ),
        _LinkCard(
          icon: Icons.people_outline,
          title: AppStrings.communityFeed,
          subtitle: AppStrings.noLinkedPatients,
          onTap: () => Navigator.pushNamed(context, CommunityPage.routeName),
        ),
        _LinkCard(
          icon: Icons.school_outlined,
          title: AppStrings.education,
          subtitle: AppStrings.educationNotMedicalAdvice,
          onTap: () => Navigator.pushNamed(context, EducationPage.routeName),
        ),
        _LinkCard(
          icon: Icons.notifications_outlined,
          title: AppStrings.inboxWithUnread,
          subtitle: _unread == null
              ? AppStrings.inbox
              : '$_unread ${AppStrings.unread.toLowerCase()}',
          onTap: () =>
              Navigator.pushNamed(context, NotificationsPage.routeName),
        ),
      ],
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}