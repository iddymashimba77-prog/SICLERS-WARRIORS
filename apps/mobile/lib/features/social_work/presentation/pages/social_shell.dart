import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/role_shell.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import 'social_caseload_page.dart';
import 'social_cases_page.dart';
import 'social_needs_page.dart';
import 'social_referrals_page.dart';

/// Dedicated social-support experience (§3) — never a copy of the doctor or
/// psychologist shell. Case work only: no financial surfaces anywhere.
class SocialShell extends StatelessWidget {
  const SocialShell({super.key});

  static const String routeName = '/social-shell';

  static List<RoleDestination> get _destinations => [
    RoleDestination(
      icon: Icons.groups_outlined,
      selectedIcon: Icons.groups,
      label: AppStrings.socialCaseload,
    ),
    RoleDestination(
      icon: Icons.folder_special_outlined,
      selectedIcon: Icons.folder_special,
      label: AppStrings.socialCases,
    ),
    RoleDestination(
      icon: Icons.checklist_outlined,
      selectedIcon: Icons.checklist,
      label: AppStrings.socialNeeds,
    ),
    RoleDestination(
      icon: Icons.forward_to_inbox_outlined,
      selectedIcon: Icons.forward_to_inbox,
      label: AppStrings.socialReferrals,
    ),
    RoleDestination(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: AppStrings.profile,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      destinations: _destinations,
      bodyFor: (context, index) {
        switch (index) {
          case 1:
            return const SocialCasesPage();
          case 2:
            return const SocialNeedsPage();
          case 3:
            return const SocialReferralsPage();
          case 4:
            return const ProfilePage();
          default:
            return const SocialCaseloadPage();
        }
      },
    );
  }
}
