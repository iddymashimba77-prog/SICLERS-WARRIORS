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
import '../../../health/data/health_repository.dart';
import '../../../health/presentation/pages/health_dashboard_page.dart';
import '../../../health/presentation/pages/symptom_form_page.dart';
import '../../../notifications/data/notifications_repository.dart';
import '../../../auth/data/token_store.dart';
import '../../../notifications/presentation/pages/notifications_page.dart';
import '../../../../shared/widgets/signed_out_gate.dart';
import '../../data/caregiver_health_repository.dart';
import 'caregiver_health_page.dart';

/// Caregiver home (FRONTEND-3).
///
/// A caregiver never sees a patient's data automatically. Linked patients,
/// health updates and medication reminders appear ONLY when the backend
/// authorizes them (`GET /api/caregivers/me/health/`); until then this
/// surface shows honest empty states — no link, no consent — plus the
/// caregiver's own authorized surfaces (community, academy, messages,
/// notifications). A transport failure is the only "load failed" + retry.
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
        avatarImageUrl: session.photoUrl,
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
  CaregiverHomeRepository({CaregiverHealthRepository? health})
      : health = health ?? CaregiverHealthRepository();

  final NotificationsRepository notifications = NotificationsRepository(
    tokenStore: EphemeralTokenStore(),
  );

  /// Consent-gated linked-patient health track client.
  final CaregiverHealthRepository health;
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

  CaregiverHealthSummary? _health;
  bool _healthLoading = true;
  bool _healthError = false;

  @override
  void initState() {
    super.initState();
    _loadUnread();
    _loadHealth();
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

  Future<void> _loadHealth() async {
    setState(() {
      _healthLoading = true;
      _healthError = false;
    });
    try {
      final summary =
          await widget.repository.health.fetchHealth(access: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _health = summary;
        _healthLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _healthError = true;
        _healthLoading = false;
      });
    }
  }

  Future<void> _recordObservation() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SymptomFormPage(
          accessToken: widget.accessToken,
          repository: HealthRepository(tokenStore: EphemeralTokenStore()),
          submit: widget.repository.health.logObservation,
          title: AppStrings.recordForPatient,
        ),
      ),
    );
    if (result == true && mounted) _loadHealth();
  }

  void _openHealthTrack() {
    Navigator.pushNamed(context, HealthDashboardPage.routeName);
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
              style: theme.textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ..._healthSections(theme),
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

  /// Linked-patient + health-updates sections, driven by one consent-gated
  /// fetch: shared loading skeleton, shared transport-error retry, then the
  /// backend's honest `no_link` / `no_consent` / `ok` states.
  List<Widget> _healthSections(ThemeData theme) {
    if (_healthLoading) {
      return [
        Text(
          AppStrings.linkedPatients.toUpperCase(),
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonCard(lines: 1, rows: 2),
      ];
    }
    if (_healthError) {
      return [
        ErrorRetryView(
          title: AppStrings.healthTracking,
          message: AppStrings.healthLoadFailed,
          onRetry: _loadHealth,
        ),
      ];
    }
    final summary = _health;
    if (summary == null) {
      return const [SizedBox.shrink()];
    }
    return [
      Text(
        AppStrings.linkedPatients.toUpperCase(),
        style: theme.textTheme.labelSmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      ..._linkedSection(summary),
      const SizedBox(height: AppSpacing.xl),
      Text(
        AppStrings.caregiverHealthUpdates.toUpperCase(),
        style: theme.textTheme.labelSmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      ..._updatesSection(summary, theme),
      if (summary.isOk) ...[
        const SizedBox(height: AppSpacing.lg),
        if (summary.canLog)
          FilledButton.tonalIcon(
            onPressed: _recordObservation,
            icon: const Icon(Icons.add_circle_outline),
            label: Text(AppStrings.recordForPatient),
          ),
        if (summary.canLog) const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _openHealthTrack,
          icon: const Icon(Icons.timeline_outlined),
          label: Text(AppStrings.openHealthTrack),
        ),
      ],
    ];
  }

  List<Widget> _linkedSection(CaregiverHealthSummary summary) {
    final patient = summary.linkedPatient;
    if (patient == null) {
      return [
        EmptyStateView(
          icon: Icons.people_outline,
          message: AppStrings.caregiverNoLinkGuidance,
        ),
      ];
    }
    return [
      Card(
        child: ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(patient.displayName),
          subtitle: Text(relationshipLabel(patient.relationshipType)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openHealthTrack,
        ),
      ),
    ];
  }

  List<Widget> _updatesSection(CaregiverHealthSummary summary, ThemeData theme) {
    if (summary.reason == 'no_link') {
      return [
        EmptyStateView(
          icon: Icons.health_and_safety_outlined,
          message: AppStrings.noHealthUpdates,
        ),
      ];
    }
    if (!summary.isOk) {
      // reason == 'no_consent': linked, but no health scope shared yet.
      return [
        EmptyStateView(
          icon: Icons.lock_outline,
          message: AppStrings.caregiverNoConsentGuidance,
        ),
      ];
    }
    return [
      if (!summary.canViewSymptoms)
        _muted(AppStrings.notSharedYet, theme)
      else if (summary.symptoms.isEmpty)
        Text(AppStrings.noSymptoms)
      else
        for (final s in summary.symptoms.take(3))
          Card(
            child: ListTile(
              dense: true,
              leading: Icon(
                s.painLevel != null && s.painLevel! >= 7
                    ? Icons.warning_amber_rounded
                    : Icons.health_and_safety_outlined,
                color: s.painLevel != null && s.painLevel! >= 7
                    ? AppColors.emergency
                    : AppColors.primary,
              ),
              title: Text(s.symptomTypeName ?? s.symptomTypeCode),
              subtitle: Text([
                if (s.painLevel != null)
                  '${AppStrings.painLevel}: ${s.painLevel}/10',
                if (s.durationMinutes != null) '${s.durationMinutes} min',
              ].join(' · ')),
            ),
          ),
      if (summary.canViewMedications) ...[
        const SizedBox(height: AppSpacing.md),
        Text(
          AppStrings.medications.toUpperCase(),
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (summary.medications.isEmpty)
          Text(AppStrings.noMedications)
        else
          for (final m in summary.medications.take(3))
            Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.medication_outlined),
                title: Text(m.label),
                subtitle: m.schedule.isEmpty ? null : Text(m.schedule),
              ),
            ),
      ],
    ];
  }

  Widget _muted(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Text(
        text,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
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
