import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import 'donations_page.dart';
import '../../../blood_donation/presentation/pages/blood_donation_page.dart';

/// Changia — contributions destination (FRONTEND-1 foundation).
///
/// Light landing shell only. Routes to the existing blood-donation and
/// verified financial-campaign surfaces. The full Donations experience is
/// built in later frontend stages.
class ChangiaHubPage extends StatelessWidget {
  const ChangiaHubPage({super.key});

  static const String routeName = '/changia';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const AppTopBar(title: AppStrings.navDonate),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              'Give what matters most.',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Support the warrior community — through blood or verified '
              'campaigns. Every contribution is tracked transparently.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppCard.action(
              onTap: () =>
                  Navigator.pushNamed(context, BloodDonationPage.routeName),
              child: _HubRow(
                icon: Icons.bloodtype_outlined,
                title: AppStrings.bloodDonation,
                subtitle: 'Request, donate or match blood',
              ),
            ),
            AppCard.action(
              onTap: () => Navigator.pushNamed(context, DonationsPage.routeName),
              child: _HubRow(
                icon: Icons.volunteer_activism_outlined,
                title: AppStrings.financialDonations,
                subtitle: 'Support verified campaigns securely',
              ),
            ),
          ],
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