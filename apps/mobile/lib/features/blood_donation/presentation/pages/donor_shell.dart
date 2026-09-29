import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/role_shell.dart';
import '../../../notifications/presentation/pages/notifications_page.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../../presentation/pages/blood_donation_page.dart';
import '../pages/donor_home_page.dart';

/// Dedicated blood-donor experience (FRONTEND-3).
///
/// Built on the real `/blood/*` endpoints only; matching/compatibility stays
/// backend-owned. Donor private contact details are never shown.
class DonorShell extends StatelessWidget {
  const DonorShell({super.key});

  static const String routeName = '/donor-shell';

  static const List<RoleDestination> _destinations = [
    RoleDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: AppStrings.donorHome,
    ),
    RoleDestination(
      icon: Icons.bloodtype_outlined,
      selectedIcon: Icons.bloodtype,
      label: AppStrings.blood,
    ),
    RoleDestination(
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications,
      label: AppStrings.notifications,
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
            return const BloodDonationPage();
          case 2:
            return const NotificationsPage();
          case 3:
            return const ProfilePage();
          default:
            return const DonorHomePage();
        }
      },
    );
  }
}