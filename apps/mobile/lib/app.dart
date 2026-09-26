import 'package:flutter/material.dart';

import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/presentation/pages/admin_panel_page.dart';
import 'features/ai_assistant/presentation/pages/ai_assistant_page.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/blood_donation/presentation/pages/blood_donation_page.dart';
import 'features/clinic/presentation/pages/clinic_page.dart';
import 'features/community/presentation/pages/community_page.dart';
import 'features/doctor_network/presentation/pages/doctor_network_page.dart';
import 'features/donations/presentation/pages/donations_page.dart';
import 'features/emergency/presentation/pages/emergency_page.dart';
import 'features/home/presentation/pages/home_page.dart';
import 'features/medical/presentation/pages/medical_profile_page.dart';
import 'features/medication/presentation/pages/medication_page.dart';
import 'features/notifications/presentation/pages/notifications_page.dart';
import 'features/profile/presentation/pages/profile_page.dart';
import 'shared/widgets/main_shell.dart';

class SicklersWarriorsApp extends StatelessWidget {
  const SicklersWarriorsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      initialRoute: LoginPage.routeName,
      routes: {
        LoginPage.routeName: (_) => const LoginPage(),
        HomePage.routeName: (_) => const HomePage(),
        ProfilePage.routeName: (_) => const ProfilePage(),
        EmergencyPage.routeName: (_) => const EmergencyPage(),
        CommunityPage.routeName: (_) => const CommunityPage(),
        MedicalProfilePage.routeName: (_) => const MedicalProfilePage(),
        MedicationPage.routeName: (_) => const MedicationPage(),
        BloodDonationPage.routeName: (_) => const BloodDonationPage(),
        DoctorNetworkPage.routeName: (_) => const DoctorNetworkPage(),
        ClinicPage.routeName: (_) => const ClinicPage(),
        DonationsPage.routeName: (_) => const DonationsPage(),
        NotificationsPage.routeName: (_) => const NotificationsPage(),
        AiAssistantPage.routeName: (_) => const AiAssistantPage(),
        AdminPanelPage.routeName: (_) => const AdminPanelPage(),
        MainShell.routeName: (_) => const MainShell(),
      },
    );
  }
}
