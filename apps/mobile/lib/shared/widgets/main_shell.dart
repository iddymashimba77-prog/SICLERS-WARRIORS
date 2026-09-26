import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../features/blood_donation/presentation/pages/blood_donation_page.dart';
import '../../features/community/presentation/pages/community_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/medical/presentation/pages/medical_profile_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';

/// Founder-driven navigation shell for the Sickler's Warriors mobile app.
///
/// Follows the approved navigation design (Stage 3, mobile-navigation):
/// a bottom `NavigationBar` with five primary destinations plus a global,
/// always-visible SOS action. Red token is reserved for emergency/danger
/// only and is used here for the SOS action — it is never a primary surface.
///
/// Destinations (adapts to role later):
///   1. Home
///   2. Health
///   3. Blood
///   4. Community
///   5. More / Profile
///
/// This is the navigation *foundation* only. Screens are wired in by each
/// feature stage; SOS remains a global, always-visible action.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  static const String routeName = '/shell';

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: AppStrings.home,
    ),
    NavigationDestination(
      icon: Icon(Icons.favorite_outline_rounded),
      selectedIcon: Icon(Icons.favorite_rounded),
      label: AppStrings.health,
    ),
    NavigationDestination(
      icon: Icon(Icons.water_drop_outlined),
      selectedIcon: Icon(Icons.water_drop),
      label: AppStrings.blood,
    ),
    NavigationDestination(
      icon: Icon(Icons.groups_outlined),
      selectedIcon: Icon(Icons.groups),
      label: AppStrings.community,
    ),
    NavigationDestination(
      icon: Icon(Icons.more_horiz_rounded),
      label: AppStrings.more,
    ),
  ];

  Widget _bodyFor(int index) {
    switch (index) {
      case 1:
        return const MedicalProfilePage();
      case 2:
        return const BloodDonationPage();
      case 3:
        return const CommunityPage();
      case 4:
        return const ProfilePage();
      default:
        return const HomePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _bodyFor(_index)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'sos',
        // Emergency-only red token; never a primary surface.
        backgroundColor: AppColors.emergency,
        foregroundColor: AppColors.onPrimary,
        tooltip: AppStrings.sos,
        onPressed: () {
          // Wired to the SOS/emergency flow in a later stage.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppStrings.emergencySupport)),
          );
        },
        child: const Icon(Icons.medical_services_outlined),
      ),
    );
  }
}
