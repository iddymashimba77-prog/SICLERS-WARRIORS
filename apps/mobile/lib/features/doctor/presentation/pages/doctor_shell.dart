import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/role_shell.dart';
import '../../../chat/presentation/pages/conversation_list_page.dart';
import '../../../notifications/presentation/pages/notifications_page.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import 'doctor_home_page.dart';

/// Dedicated doctor experience (FRONTEND-3) — never a copy of the patient
/// shell. The backend authorizes every surface; unavailable areas render
/// honest empty states rather than fabricated data.
class DoctorShell extends StatelessWidget {
  const DoctorShell({super.key});

  static const String routeName = '/doctor-shell';

  static const List<RoleDestination> _destinations = [
    RoleDestination(
      icon: Icons.medical_services_outlined,
      selectedIcon: Icons.medical_services,
      label: AppStrings.doctorHome,
    ),
    RoleDestination(
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
      label: AppStrings.messages,
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
            return const ConversationListPage();
          case 2:
            return const NotificationsPage();
          case 3:
            return const ProfilePage();
          default:
            return const DoctorHomePage();
        }
      },
    );
  }
}