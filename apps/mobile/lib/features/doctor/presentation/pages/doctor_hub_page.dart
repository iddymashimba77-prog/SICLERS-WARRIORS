import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../../auth/presentation/widgets/session_scope.dart';
import '../../../chat/presentation/pages/conversation_list_page.dart';
import '../../../clinic/presentation/pages/clinic_page.dart';
import '../../../doctor_network/presentation/pages/doctor_network_page.dart';
import '../../../education/presentation/pages/doctor_education_page.dart';

/// Daktari — doctor experience destination (FRONTEND-1 foundation).
///
/// Light landing shell only. It routes to the existing verified-doctor
/// discovery, clinic/calendar and messaging surfaces. The richer Doctor
/// experience (patient list, authorised records, treatment notes,
/// availability) is built in later frontend stages.
class DoctorHubPage extends StatelessWidget {
  const DoctorHubPage({super.key});

  static const String routeName = '/daktari';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // My articles is the authoring surface: only grant the entry to users the
    // backend has already given education.publish (patients stay read-only).
    final canPublish =
        SessionScope.controllerOf(context).permissions.contains('education.publish');
    final children = <Widget>[
      Text(
        'Verified care, close to you.',
        style: theme.textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Find verified sickle-cell care, book appointments and keep a '
        'secure line to your care team.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: AppSpacing.xl),
      AppCard.action(
        onTap: () =>
            Navigator.pushNamed(context, DoctorNetworkPage.routeName),
        child: _HubRow(
          icon: Icons.medical_services_outlined,
          title: AppStrings.verifiedDoctors,
          subtitle: 'Discover verified doctors near you',
        ),
      ),
      AppCard.action(
        onTap: () => Navigator.pushNamed(context, ClinicPage.routeName),
        child: _HubRow(
          icon: Icons.event_available_outlined,
          title: AppStrings.clinicCalendar,
          subtitle: 'Appointments and clinic visits',
        ),
      ),
      AppCard.action(
        onTap: () =>
            Navigator.pushNamed(context, ConversationListPage.routeName),
        child: _HubRow(
          icon: Icons.chat_bubble_outline,
          title: AppStrings.messages,
          subtitle: 'Private messages with your care team',
        ),
      ),
      if (canPublish)
        AppCard.action(
          onTap: () =>
              Navigator.pushNamed(context, DoctorEducationPage.routeName),
          child: _HubRow(
            icon: Icons.menu_book_outlined,
            title: 'My articles',
            subtitle: 'Write Warrior Academy content and attach patient handouts',
          ),
        ),
      const SizedBox(height: AppSpacing.xl),
      Text(
        AppStrings.comingSoon,
        style: theme.textTheme.labelSmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      const Text(
        'Treatment plans and authorised records arrive with the doctor '
        'experience stages.',
        style: TextStyle(fontSize: 13, height: 1.4),
      ),
    ];
    return Scaffold(
      appBar: const AppTopBar(title: AppStrings.navDoctor),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: children,
        ),
      ),
    );
  }
}

class _HubRow extends StatelessWidget {
  const _HubRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.xxs),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, size: 20),
      ],
    );
  }
}