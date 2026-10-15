import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../public/presentation/pages/public_home_page.dart';
import '../controllers/auth_controller.dart';
import '../widgets/session_scope.dart';

/// AUTH-2 — organization / facility identity page.
///
/// Surfaced for HOSPITAL / HEALTHCARE_STAFF / ORGANIZATION sessions. It shows
/// the facility identity the server asserts (never inferred from account
/// type) and its verification state. Memberships without a verified facility
/// are reported honestly as pending — never treated as approved.
class OrganizationVerificationPage extends StatelessWidget {
  const OrganizationVerificationPage({super.key, this.controller});

  static const String routeName = '/org-status';

  final AuthController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppLocalizations.of(context);
    final auth = controller ?? SessionScope.controllerOf(context);
    final facility = auth.facility;
    final name = facility?['name'] as String? ?? s.tr('org.yourOrganization');
    final isVerified = facility?['is_verified'] == true;
    final facilityType =
        (facility?['facility_type'] as String? ?? s.tr('org.facilityFallback'))
            .toLowerCase();

    return Scaffold(
      appBar: AppBar(title: Text(s.tr('auth.organization'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Icon(
                  isVerified ? Icons.verified_outlined : Icons.hourglass_top_outlined,
                  size: 72,
                  color: isVerified ? Colors.green : AppColors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  isVerified
                      ? '$name ${s.tr('org.verifiedSuffix')}'
                      : s.tr('role.verificationPending'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  isVerified
                      ? s
                          .tr('org.verifiedBody')
                          .replaceAll('{name}', name)
                          .replaceAll('{type}', facilityType)
                      : s.tr('org.pendingBody').replaceAll('{type}', facilityType),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      PublicHomePage.routeName,
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.home_outlined),
                  label: Text(s.tr('common.goHome')),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await auth.logout();
                    if (context.mounted) {
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        PublicHomePage.routeName,
                        (route) => false,
                      );
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: Text(AppStrings.signOut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}