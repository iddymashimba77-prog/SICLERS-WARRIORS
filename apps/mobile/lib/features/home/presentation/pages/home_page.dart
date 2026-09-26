import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/widgets/feature_card.dart';
import '../../../blood_donation/presentation/pages/blood_donation_page.dart';
import '../../../community/presentation/pages/community_page.dart';
import '../../../doctor_network/presentation/pages/doctor_network_page.dart';
import '../../../medical/presentation/pages/medical_profile_page.dart';
import '../../../medication/presentation/pages/medication_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const String routeName = '/';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: AppStrings.notifications,
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              AppStrings.appTagline,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          FeatureCard(
            icon: Icons.medical_services_outlined,
            title: AppStrings.medicalProfile,
            subtitle: 'Manage your sickle cell health profile',
            color: AppColors.primary,
            onTap: () =>
                Navigator.pushNamed(context, MedicalProfilePage.routeName),
          ),
          FeatureCard(
            icon: Icons.medication_outlined,
            title: AppStrings.medicationReminders,
            subtitle: 'Track medication schedules & reminders',
            color: AppColors.info,
            onTap: () => Navigator.pushNamed(context, MedicationPage.routeName),
          ),
          FeatureCard(
            icon: Icons.bloodtype_outlined,
            title: AppStrings.bloodDonation,
            subtitle: 'Find donors, donate & request blood',
            color: Color(0xFFC62828),
            onTap: () =>
                Navigator.pushNamed(context, BloodDonationPage.routeName),
          ),
          FeatureCard(
            icon: Icons.local_hospital_outlined,
            title: AppStrings.doctorNetwork,
            subtitle: 'Connect with verified doctors',
            color: AppColors.success,
            onTap: () =>
                Navigator.pushNamed(context, DoctorNetworkPage.routeName),
          ),
          FeatureCard(
            icon: Icons.groups,
            title: AppStrings.community,
            subtitle: 'Join the warrior community',
            color: AppColors.info,
            onTap: () => Navigator.pushNamed(context, CommunityPage.routeName),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.sos),
              label: const Text(AppStrings.sos),
            ),
          ),
        ],
      ),
    );
  }
}
