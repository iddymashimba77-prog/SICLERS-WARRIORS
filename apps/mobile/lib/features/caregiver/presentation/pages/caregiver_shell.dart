import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/role_shell.dart';
import '../../../community/presentation/pages/community_page.dart';
import '../../../education/presentation/pages/education_page.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../pages/caregiver_home_page.dart';

/// Dedicated caregiver experience (FRONTEND-3).
///
/// Caregivers never see all patient information automatically — linked
/// patients and their data appear only under backend authorization + consent.
/// Until then they get honest empty states plus their own authorized surfaces.
class CaregiverShell extends StatelessWidget {
  const CaregiverShell({super.key});

  static const String routeName = '/caregiver-shell';

  static const List<RoleDestination> _destinations = [
    RoleDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: AppStrings.caregiverHome,
    ),
    RoleDestination(
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      label: AppStrings.communityFeed,
    ),
    RoleDestination(
      icon: Icons.school_outlined,
      selectedIcon: Icons.school,
      label: AppStrings.education,
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
            return const CommunityPage();
          case 2:
            return const EducationPage();
          case 3:
            return const ProfilePage();
          default:
            return const CaregiverHomePage();
        }
      },
    );
  }
}