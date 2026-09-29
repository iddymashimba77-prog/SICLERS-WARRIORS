import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../chat/presentation/pages/conversation_list_page.dart';

/// Clinic / appointment calendar destination (FRONTEND-3).
///
/// No appointment service is exposed by the backend yet, so this shows an
/// honest state — no fabricated bookings — and directs users to their care
/// team via Messages.
class ClinicPage extends StatelessWidget {
  const ClinicPage({super.key});

  static const String routeName = '/clinic';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.clinicCalendar)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Card(
              color: AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  children: [
                    const Icon(
                      Icons.event_busy_outlined,
                      size: 56,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      AppStrings.noAppointments,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      AppStrings.noAppointmentsToday,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appointment booking is being set up. No visits can be '
                      'scheduled through the app yet.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      AppStrings.noAppointmentsToday,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        ConversationListPage.routeName,
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text(AppStrings.reachCareTeam),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(AppStrings.navDoctor),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}