import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/responsive/responsive.dart';
import '../../features/donations/presentation/pages/changia_hub_page.dart';
import '../../features/doctor/presentation/pages/doctor_hub_page.dart';
import '../../features/emergency/presentation/pages/emergency_page.dart';
import '../../features/health/presentation/pages/health_dashboard_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';

/// Sickler's Warriors — adaptive patient application shell (FRONTEND-1).
///
/// - Compact (phones): TopBar + content + **five-tab bottom navigation**.
/// - Medium (tablets): top bar + side `NavigationRail`.
/// - Expanded/Large (desktop/web): side `NavigationRail` with labels.
///
/// The five primary patient destinations:
///   1. Nyumbani (home dashboard)
///   2. Daktari (doctor discovery, appointments, communication)
///   3. Tiba (medication, health tracking, records, timeline)
///   4. Changia (blood donation, financial donations)
///   5. Wasifu (profile, preferences, privacy, settings)
///
/// An SOS action stays globally visible on every size. Tab bodies live in an
/// [IndexedStack] so each destination keeps its own navigation state.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  static const String routeName = '/shell';

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  List<_Destination> _destinationsOf(BuildContext context) {
    final s = AppLocalizations.of(context);
    return [
      _Destination(icon: Icons.home_outlined, selected: Icons.home, label: s.tr('nav.home')),
      _Destination(
        icon: Icons.medical_services_outlined,
        selected: Icons.medical_services_outlined,
        label: s.tr('nav.doctor'),
      ),
      _Destination(
        icon: Icons.medication_outlined,
        selected: Icons.medication,
        label: s.tr('nav.treatment'),
      ),
      _Destination(
        icon: Icons.favorite_outline,
        selected: Icons.favorite,
        label: s.tr('nav.donate'),
      ),
      _Destination(
        icon: Icons.person_outline,
        selected: Icons.person,
        label: s.tr('nav.profile'),
      ),
    ];
  }

  Widget _bodyFor(int index) {
    switch (index) {
      case 1:
        return const DoctorHubPage();
      case 2:
        return const HealthDashboardPage();
      case 3:
        return const ChangiaHubPage();
      case 4:
        return const ProfilePage();
      default:
        return const HomePage();
    }
  }

  void _openSos() {
    Navigator.of(context).pushNamed(EmergencyPage.routeName);
  }

  Widget _sosButton() {
    return FloatingActionButton(
      heroTag: 'sos',
      // Emergency-only red token; never a primary surface.
      backgroundColor: AppColors.emergency,
      foregroundColor: AppColors.onPrimary,
      tooltip: AppLocalizations.of(context).tr('sos.label'),
      onPressed: _openSos,
      child: const Icon(Icons.sos),
    );
  }

  Widget _content(BoxConstraints constraints) {
    final bool compact = AppLayout.useBottomNavigation(constraints);
    final destinations = _destinationsOf(context);
    final Widget body = IndexedStack(index: _index, children: [
      for (var i = 0; i < destinations.length; i++) _bodyFor(i),
    ]);

    if (compact) {
      return body;
    }

    final showLabels = AppLayout.showRailLabels(constraints);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavigationRail(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          labelType: showLabels
              ? NavigationRailLabelType.all
              : NavigationRailLabelType.none,
          leading: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: AppHomeMark(),
          ),
          minExtendedWidth: 120,
          destinations: [
            for (final d in destinations)
              NavigationRailDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selected),
                label: Text(d.label),
              ),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: body),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool compact = AppLayout.useBottomNavigation(constraints);
        final destinations = _destinationsOf(context);
        return Scaffold(
          body: _content(constraints),
          bottomNavigationBar: compact
              ? NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: [
                    for (final d in destinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selected),
                        label: d.label,
                      ),
                  ],
                )
              : null,
          floatingActionButton: _sosButton(),
        );
      },
    );
  }
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.selected,
    required this.label,
  });

  final IconData icon;
  final IconData selected;
  final String label;
}

/// Small brand mark rendered above the rail and on the desktop shell head.
class AppHomeMark extends StatelessWidget {
  const AppHomeMark({super.key, this.dark = false});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final Color bg = dark ? AppColors.navy : AppColors.blue;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(
        Icons.favorite,
        color: AppColors.textOnDark,
        size: 20,
      ),
    );
  }
}