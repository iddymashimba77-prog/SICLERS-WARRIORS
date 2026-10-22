import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/role_shell.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import 'psychology_assessments_page.dart';
import 'psychology_caseload_page.dart';
import 'psychology_notes_page.dart';
import 'psychology_referrals_page.dart';

/// Dedicated psychologist experience (§2) — never a copy of the doctor shell.
/// Every body performs its own consent-checked API calls; unavailable areas
/// render honest empty states rather than fabricated data.
class PsychologyShell extends StatelessWidget {
  const PsychologyShell({super.key});

  static const String routeName = '/psychology-shell';

  static List<RoleDestination> get _destinations => [
    RoleDestination(
      icon: Icons.groups_outlined,
      selectedIcon: Icons.groups,
      label: AppStrings.psychCaseload,
    ),
    RoleDestination(
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
      label: AppStrings.psychAssessments,
    ),
    RoleDestination(
      icon: Icons.note_alt_outlined,
      selectedIcon: Icons.note_alt,
      label: AppStrings.psychNotes,
    ),
    RoleDestination(
      icon: Icons.forward_to_inbox_outlined,
      selectedIcon: Icons.forward_to_inbox,
      label: AppStrings.psychReferrals,
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
            return const PsychologyAssessmentsPage();
          case 2:
            return const PsychologyNotesPage();
          case 3:
            return const PsychologyReferralsPage();
          case 4:
            return const ProfilePage();
          default:
            return const PsychologyCaseloadPage();
        }
      },
    );
  }
}
