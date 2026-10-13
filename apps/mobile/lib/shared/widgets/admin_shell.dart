import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/admin/domain/admin_authz.dart';
import '../../features/admin/presentation/pages/admin_ai_monitoring_page.dart';
import '../../features/admin/presentation/pages/admin_analytics_page.dart';
import '../../features/admin/presentation/pages/admin_audit_logs_page.dart';
import '../../features/admin/presentation/pages/admin_blood_requests_page.dart';
import '../../features/admin/presentation/pages/admin_broadcast_page.dart';
import '../../features/admin/presentation/pages/admin_campaigns_page.dart';
import '../../features/admin/presentation/pages/admin_dashboard_page.dart';
import '../../features/admin/presentation/pages/admin_doctors_page.dart';
import '../../features/admin/presentation/pages/admin_content_management_page.dart';
import '../../features/admin/presentation/pages/admin_education_content_page.dart';
import '../../features/admin/presentation/pages/admin_facilities_page.dart';
import '../../features/admin/presentation/pages/admin_finance_page.dart';
import '../../features/admin/presentation/pages/admin_moderation_page.dart';
import '../../features/admin/presentation/pages/admin_roles_page.dart';
import '../../features/admin/presentation/pages/admin_security_events_page.dart';
import '../../features/admin/presentation/pages/admin_users_page.dart';
import '../../features/auth/presentation/widgets/session_scope.dart';
import 'app_avatar.dart';
import 'app_top_bar.dart';
import '../../core/theme/app_shapes.dart';

/// Sickler's Warriors — ADMIN-3 admin shell.
///
/// The navigation is built from the authenticated session's server-issued
/// `permission_codes` (and roles): only sections the backend actually
/// authorizes are shown, and every nested surface is still guarded server-side.
/// Sections without a backend surface are intentionally absent — there is no
/// fabricated admin module in this portal.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.maybeOf(context);
    final sections = session == null
        ? <AdminSection>[]
        : adminSectionsFor(
            permissions: session.permissions,
            roles: session.roles,
          );

    if (sections.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.lock_outline, size: 40),
              SizedBox(height: 16),
              Text('No admin sections are available for this session.'),
            ],
          ),
        ),
      );
    }

    final safeIndex = _index < sections.length ? _index : 0;
    final section = sections[safeIndex];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final bool useDrawer = width < 840;
        final adminName = session?.displayName ?? 'Admin';
        final adminSub = session?.roles.join(', ') ?? 'Administrator';
        return Scaffold(
          drawer: useDrawer ? _buildDrawer(sections) : null,
          body: Row(
            children: [
              if (!useDrawer) ..._rail(sections, safeIndex, adminName, adminSub),
              Expanded(
                child: Column(
                  children: [
                    AppTopBar(
                      title: section.label,
                      leading: useDrawer ? Builder(builder: _drawerButton) : null,
                      onNotificationsTap: () {},
                      avatarName: adminName,
                    ),
                    Expanded(child: _content(section)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _rail(
    List<AdminSection> sections,
    int index,
    String adminName,
    String adminSub,
  ) {
    return [
      _AdminSidebar(
        sections: sections,
        selectedIndex: index,
        collapsed: _collapsed,
        adminName: adminName,
        adminSub: adminSub,
        onSelect: (i) => setState(() => _index = i),
        onToggleCollapse: () => setState(() => _collapsed = !_collapsed),
      ),
      const VerticalDivider(width: 1),
    ];
  }

  Widget _buildDrawer(List<AdminSection> sections) {
    return Drawer(
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: _AdminSidebar(
                sections: sections,
                selectedIndex: _index,
                collapsed: false,
                adminName: '',
                adminSub: '',
                onSelect: (i) {
                  setState(() => _index = i);
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerButton(BuildContext context) {
    return IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu),
      onPressed: () => Scaffold.of(context).openDrawer(),
    );
  }

  Widget _content(AdminSection section) {
    switch (section.label) {
      case 'Users':
        return const AdminUsersPage();
      case 'Doctors':
        return const AdminDoctorsPage();
      case 'Organizations':
        return const AdminFacilitiesPage();
      case 'Blood Verification':
        return const AdminBloodRequestsPage();
      case 'Campaigns':
        return const AdminCampaignsPage();
      case 'Roles & Permissions':
        return const AdminRolesPage();
      case 'Content Review':
        return const AdminEducationContentPage();
      case 'News':
        return const AdminNewsPage();
      case 'Announcements':
        return const AdminTickerPage();
      case 'Moderation':
        return const AdminModerationPage();
      case 'Finance':
        return const AdminFinancePage();
      case 'Broadcast':
        return const AdminBroadcastPage();
      case 'Audit Logs':
        return const AdminAuditLogsPage();
      case 'Security Events':
        return const AdminSecurityEventsPage();
      case 'AI Monitoring':
        return const AdminAiMonitoringPage();
      default: // Dashboard + Analytics
        return section.label == 'Analytics'
            ? const AdminAnalyticsPage()
            : const AdminDashboardPage();
    }
  }
}

/// Dark navy sidebar with active state, collapse and a profile area.
class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.sections,
    required this.selectedIndex,
    required this.onSelect,
    required this.adminName,
    required this.adminSub,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  final List<AdminSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final String adminName;
  final String adminSub;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: collapsed ? 76 : 248,
      color: AppColors.navy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? AppSpacing.sm : AppSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.blue,
                      borderRadius: AppShapes.medium,
                    ),
                    child: const Icon(
                      Icons.favorite,
                      color: AppColors.textOnDark,
                      size: 20,
                    ),
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: AppSpacing.md),
                    const Expanded(
                      child: Text(
                        'Warriors Admin',
                        style: TextStyle(
                          color: AppColors.textOnDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(color: AppColors.dividerOnDark, height: 1),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              children: [
                for (var i = 0; i < sections.length; i++)
                  _SidebarTile(
                    section: sections[i],
                    selected: i == selectedIndex,
                    collapsed: collapsed,
                    onTap: () => onSelect(i),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              children: [
                if (onToggleCollapse != null)
                  Align(
                    alignment: collapsed
                        ? Alignment.center
                        : Alignment.centerRight,
                    child: IconButton(
                      tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
                      icon: Icon(
                        collapsed
                            ? Icons.chevron_right
                            : Icons.chevron_left,
                        color: AppColors.textOnDark.withValues(alpha: 0.85),
                      ),
                      onPressed: onToggleCollapse,
                    ),
                  ),
                const Divider(color: AppColors.dividerOnDark, height: 17),
                if (adminName.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: collapsed ? 0 : AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      mainAxisAlignment: collapsed
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      children: [
                        AppAvatar(
                          name: adminName,
                          radius: 18,
                          backgroundColor: AppColors.blue,
                        ),
                        if (!collapsed) ...[
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  adminName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textOnDark,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  adminSub,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textOnDark.withValues(
                                      alpha: 0.7,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.section,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final AdminSection section;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color contentColor =
        selected ? Colors.white : AppColors.textOnDark.withValues(alpha: 0.72);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? AppColors.blue.withValues(alpha: 0.35) : Colors.transparent,
        borderRadius: AppShapes.tile,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppShapes.tile,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? AppSpacing.sm : AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            child: Row(
              children: [
                Icon(
                  selected ? section.selectedIcon : section.icon,
                  color: contentColor,
                  size: 22,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      section.label,
                      style: TextStyle(
                        color: contentColor,
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}