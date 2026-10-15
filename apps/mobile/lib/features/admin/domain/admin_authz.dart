/// Admin-3 authorization domain: permission codes + navigable sections.
///
/// The backend is the single authority — every code below mirrors a real
/// DRF permission code (`backend/accounts/permissions.py` + the seeded role
/// grant matrices). The shell renders a section only when the session holds
/// the matching code; every action is still re-enforced server-side. Codes
/// are never invented here; sections without a backend surface are not listed.
library;

import 'package:flutter/material.dart';

/// Backend permission codes used to gate the portal sections (ADMIN-3).
abstract final class AdminPermissions {
  static const String usersManage = 'admin.users.manage';
  static const String doctorsVerify = 'doctors.verify';
  static const String facilitiesVerify = 'facilities.verify';
  static const String bloodVerify = 'blood_requests.verify';
  static const String campaignsVerify = 'campaigns.verify';
  static const String rolesView = 'admin.roles.manage';
  static const String permissionsManage = 'admin.permissions.manage';
  static const String educationReview = 'education.review';
  static const String communityModerate = 'community.moderate';
  static const String donationsView = 'donations.view';
  static const String donationsRefund = 'donations.refund';
  static const String broadcast = 'notifications.broadcast';
  static const String auditView = 'audit_logs.view';
  static const String auditExport = 'audit_logs.export';
  static const String auditAdminRead = 'admin.audit.read';
  static const String analyticsView = 'analytics.view';
  static const String contentNewsManage = 'content.news.manage';
  static const String contentTickerManage = 'content.ticker.manage';
}

/// A permission-gated destination in the admin shell.
class AdminSection {
  const AdminSection({
    required this.label,
    required this.labelKey,
    required this.icon,
    required this.selectedIcon,
    required this.permissions,
  });

  /// Stable English identifier, also used as the routing switch key.
  final String label;

  /// Localization key for the sidebar and top bar display text.
  final String labelKey;
  final IconData icon;
  final IconData selectedIcon;

  /// Permission codes; the section renders if ANY matches.
  final Set<String>? permissions;
}

/// The full, ordered portal catalog. Sections are rendered conditionally from
/// the authenticated session's `permission_codes` (mirror of the backend
/// grants). No fabricated modules — every entry maps to a real endpoint.
List<AdminSection> adminSectionsFor({
  required List<String> permissions,
  required List<String> roles,
}) {
  final has = permissions.contains;
  return [
    if (has(AdminPermissions.analyticsView))
      const AdminSection(
        label: 'Dashboard',
        labelKey: 'admin.nav.dashboard',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        permissions: {AdminPermissions.analyticsView},
      ),
    if (has(AdminPermissions.usersManage))
      const AdminSection(
        label: 'Users',
        labelKey: 'admin.nav.users',
        icon: Icons.groups_outlined,
        selectedIcon: Icons.groups,
        permissions: {AdminPermissions.usersManage},
      ),
    if (has(AdminPermissions.doctorsVerify))
      const AdminSection(
        label: 'Doctors',
        labelKey: 'admin.nav.doctors',
        icon: Icons.medical_services_outlined,
        selectedIcon: Icons.medical_services,
        permissions: {AdminPermissions.doctorsVerify},
      ),
    if (has(AdminPermissions.facilitiesVerify))
      const AdminSection(
        label: 'Organizations',
        labelKey: 'admin.nav.organizations',
        icon: Icons.business_outlined,
        selectedIcon: Icons.business,
        permissions: {AdminPermissions.facilitiesVerify},
      ),
    if (has(AdminPermissions.bloodVerify))
      const AdminSection(
        label: 'Blood Verification',
        labelKey: 'admin.nav.bloodVerification',
        icon: Icons.bloodtype_outlined,
        selectedIcon: Icons.bloodtype,
        permissions: {AdminPermissions.bloodVerify},
      ),
    if (has(AdminPermissions.campaignsVerify))
      const AdminSection(
        label: 'Campaigns',
        labelKey: 'admin.nav.campaigns',
        icon: Icons.campaign_outlined,
        selectedIcon: Icons.campaign,
        permissions: {AdminPermissions.campaignsVerify},
      ),
    if (has(AdminPermissions.rolesView))
      const AdminSection(
        label: 'Roles & Permissions',
        labelKey: 'admin.nav.rolesPermissions',
        icon: Icons.security_outlined,
        selectedIcon: Icons.security,
        permissions: {AdminPermissions.rolesView},
      ),
    if (has(AdminPermissions.educationReview))
      const AdminSection(
        label: 'Content Review',
        labelKey: 'admin.nav.contentReview',
        icon: Icons.article_outlined,
        selectedIcon: Icons.article,
        permissions: {AdminPermissions.educationReview},
      ),
    if (has(AdminPermissions.contentNewsManage))
      const AdminSection(
        label: 'News',
        labelKey: 'admin.nav.news',
        icon: Icons.newspaper_outlined,
        selectedIcon: Icons.newspaper,
        permissions: {AdminPermissions.contentNewsManage},
      ),
    if (has(AdminPermissions.contentTickerManage))
      const AdminSection(
        label: 'Announcements',
        labelKey: 'admin.nav.announcements',
        icon: Icons.campaign_outlined,
        selectedIcon: Icons.campaign,
        permissions: {AdminPermissions.contentTickerManage},
      ),
    if (has(AdminPermissions.communityModerate))
      const AdminSection(
        label: 'Moderation',
        labelKey: 'admin.nav.moderation',
        icon: Icons.admin_panel_settings_outlined,
        selectedIcon: Icons.admin_panel_settings,
        permissions: {AdminPermissions.communityModerate},
      ),
    if (has(AdminPermissions.donationsView))
      const AdminSection(
        label: 'Finance',
        labelKey: 'admin.nav.finance',
        icon: Icons.account_balance_outlined,
        selectedIcon: Icons.account_balance,
        permissions: {AdminPermissions.donationsView},
      ),
    if (has(AdminPermissions.broadcast))
      const AdminSection(
        label: 'Broadcast',
        labelKey: 'admin.nav.broadcast',
        icon: Icons.campaign_outlined,
        selectedIcon: Icons.campaign,
        permissions: {AdminPermissions.broadcast},
      ),
    if (has(AdminPermissions.auditView))
      const AdminSection(
        label: 'Audit Logs',
        labelKey: 'admin.nav.auditLogs',
        icon: Icons.history_outlined,
        selectedIcon: Icons.history,
        permissions: {AdminPermissions.auditView},
      ),
    if (has(AdminPermissions.auditAdminRead))
      const AdminSection(
        label: 'Security Events',
        labelKey: 'admin.nav.securityEvents',
        icon: Icons.shield_outlined,
        selectedIcon: Icons.shield,
        permissions: {AdminPermissions.auditAdminRead},
      ),
    if (has(AdminPermissions.analyticsView))
      const AdminSection(
        label: 'Analytics',
        labelKey: 'admin.nav.analytics',
        icon: Icons.insert_chart_outlined,
        selectedIcon: Icons.insert_chart,
        permissions: {AdminPermissions.analyticsView},
      ),
    if (has(AdminPermissions.auditAdminRead))
      const AdminSection(
        label: 'AI Monitoring',
        labelKey: 'admin.nav.aiMonitoring',
        icon: Icons.psychology_outlined,
        selectedIcon: Icons.psychology,
        permissions: {AdminPermissions.auditAdminRead},
      ),
  ];
}