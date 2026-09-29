import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/responsive/responsive.dart';
import '../../features/emergency/presentation/pages/emergency_page.dart';
import 'main_shell.dart' show AppHomeMark;

/// Adaptive shell for the staff/role experiences (FRONTEND-3).
///
/// Mirrors the patient [MainShell] chrome (announced nav, SOS) so every role
/// surface feels like the same product, but each role supplies its own
/// destinations and bodies. The backend remains the authorization authority:
/// every body performs its own role-guarded API calls.
class RoleShell extends StatefulWidget {
  const RoleShell({
    super.key,
    required this.destinations,
    required this.bodyFor,
    this.initialIndex = 0,
    this.includeSos = true,
  });

  final List<RoleDestination> destinations;
  final Widget Function(BuildContext context, int index) bodyFor;
  final int initialIndex;
  final bool includeSos;

  static const String home = 'Home';

  @override
  State<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<RoleShell> {
  late int _index = widget.initialIndex;

  void _openSos() {
    Navigator.of(context).pushNamed(EmergencyPage.routeName);
  }

  @override
  Widget build(BuildContext context) {
    final destinations = widget.destinations;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool compact = AppLayout.useBottomNavigation(constraints);
        final Widget body = IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < destinations.length; i++)
              widget.bodyFor(context, i),
          ],
        );

        Widget? navigation;
        if (compact) {
          navigation = NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final d in destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          );
        } else {
          final showLabels = AppLayout.showRailLabels(constraints);
          navigation = Row(
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
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          );
        }

        return Scaffold(
          body: compact ? body : navigation,
          bottomNavigationBar: compact ? navigation : null,
          floatingActionButton: widget.includeSos
              ? FloatingActionButton(
                  heroTag: 'role-sos',
                  backgroundColor: AppColors.emergency,
                  foregroundColor: AppColors.onPrimary,
                  tooltip: AppStrings.sos,
                  onPressed: _openSos,
                  child: const Icon(Icons.sos),
                )
              : null,
        );
      },
    );
  }
}

class RoleDestination {
  const RoleDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}