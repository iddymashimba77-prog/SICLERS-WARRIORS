/// AUTH-2 — post-auth routing resolver.
///
/// Decides which experience(s) a session may start from, using only the
/// server-asserted session (roles + verification state from /auth/me). The
/// backend remains the security authority; this is purely a routing hint.
library;

import 'package:flutter/material.dart';

import 'role_gate.dart';

/// One selectable post-login destination for [SessionRouter].
class AppContext {
  const AppContext({
    required this.id,
    required this.route,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String id;
  final String route;
  final String title;
  final String subtitle;
  final IconData icon;
}

/// Resolves role-aware post-auth routing (AUTH-2).
///
/// Rules:
/// * Care professionals (DOCTOR / PSYCHOLOGIST / SOCIAL_SUPPORT) route to the
///   clinical dashboard only when the server asserts
///   `doctor_verification_status == APPROVED`; PENDING/REJECTED/SUSPENDED (or
///   absent) resolve to the verification-status screen — never the dashboard.
/// * Multiple contexts (e.g. PATIENT + BLOOD_DONOR) resolve to a "Continue
///   as" selection, never to a silently-dropped role.
/// * Facility operators (HOSPITAL / CLINIC / ORGANIZATION) surface an
///   organization context (facility identity + verification); they never enter
///   the patient shell just because no dedicated hospital shell exists yet.
/// * Unknown/empty sessions fall back to the patient shell as the public
///   default only when at least one role exists (legacy behaviour).
class SessionRouter {
  const SessionRouter._();

  static const AppContext admin = AppContext(
    id: 'admin',
    route: '/admin',
    title: 'Administrator',
    subtitle: 'Platform administration',
    icon: Icons.admin_panel_settings_outlined,
  );

  static const AppContext doctorVerified = AppContext(
    id: 'doctor',
    route: '/doctor-shell',
    title: 'Doctor',
    subtitle: 'Clinical dashboard',
    icon: Icons.medical_services_outlined,
  );

  static const AppContext doctorPending = AppContext(
    id: 'doctor-pending',
    route: '/doctor-status',
    title: 'Doctor',
    subtitle: 'Verification pending',
    icon: Icons.hourglass_top_outlined,
  );

  static const AppContext bloodDonor = AppContext(
    id: 'blood-donor',
    route: '/donor-shell',
    title: 'Blood Donor',
    subtitle: 'Donation centre',
    icon: Icons.bloodtype_outlined,
  );

  static const AppContext caregiver = AppContext(
    id: 'caregiver',
    route: '/caregiver-shell',
    title: 'Caregiver',
    subtitle: 'Care coordination',
    icon: Icons.family_restroom_outlined,
  );

  static const AppContext patient = AppContext(
    id: 'patient',
    route: '/shell',
    title: 'Patient',
    subtitle: 'Health & community',
    icon: Icons.favorite_outline,
  );

  static const AppContext organization = AppContext(
    id: 'organization',
    route: '/org-status',
    title: 'Organization',
    subtitle: 'Facility identity',
    icon: Icons.account_balance_outlined,
  );

  static const AppContext workspace = AppContext(
    id: 'workspace',
    route: '/role-workspace',
    title: 'Role',
    subtitle: 'Custom workspace',
    icon: Icons.workspaces_outlined,
  );

  static const AppContext psychologistVerified = AppContext(
    id: 'psychologist',
    route: '/doctor-shell',
    title: 'Psychologist',
    subtitle: 'Mental health support',
    icon: Icons.psychology_outlined,
  );

  static const AppContext psychologistPending = AppContext(
    id: 'psychologist-pending',
    route: '/doctor-status',
    title: 'Psychologist',
    subtitle: 'Verification pending',
    icon: Icons.psychology_outlined,
  );

  static const AppContext socialSupportVerified = AppContext(
    id: 'social-support',
    route: '/doctor-shell',
    title: 'Social Support',
    subtitle: 'Care coordination',
    icon: Icons.support_agent_outlined,
  );

  static const AppContext socialSupportPending = AppContext(
    id: 'social-support-pending',
    route: '/doctor-status',
    title: 'Social Support',
    subtitle: 'Verification pending',
    icon: Icons.support_agent_outlined,
  );

  /// Ordered list of contexts available to the session (deduplicated).
  static List<AppContext> contextsFor({
    required List<String> roles,
    String? doctorVerificationStatus,
  }) {
    final contexts = <AppContext>[];
    void add(AppContext ctx) {
      if (contexts.any((c) => c.id == ctx.id)) return;
      contexts.add(ctx);
    }

    if (AppRoles.isAdminRole(roles)) add(admin);
    if (roles.contains(AppRoles.doctor)) {
      if (doctorVerificationStatus == 'APPROVED') {
        add(doctorVerified);
      } else {
        add(doctorPending);
      }
    }
    if (roles.contains('PSYCHOLOGIST')) {
      add(doctorVerificationStatus == 'APPROVED'
          ? psychologistVerified
          : psychologistPending);
    }
    if (roles.contains('SOCIAL_SUPPORT')) {
      add(doctorVerificationStatus == 'APPROVED'
          ? socialSupportVerified
          : socialSupportPending);
    }
    if (roles.contains('BLOOD_DONOR')) add(bloodDonor);
    if (roles.contains('CAREGIVER')) add(caregiver);
    if (AppRoles.isPatient(roles)) add(patient);
    if ({'HOSPITAL', 'CLINIC', 'HEALTHCARE_STAFF', 'ORGANIZATION'}
        .intersection(roles.toSet())
        .isNotEmpty) {
      add(organization);
    }
    // Admin-created roles that this build has no dedicated shell for (REQ-4)
    // must still get an honest workspace instead of a silent patient fallback.
    if (roles.any((role) => !_knownRoles.contains(role))) add(workspace);
    if (contexts.isEmpty) add(patient);
    return contexts;
  }

  static const Set<String> _knownRoles = {
    'ADMIN',
    'SUPER_ADMIN',
    AppRoles.doctor,
    'PSYCHOLOGIST',
    'SOCIAL_SUPPORT',
    'BLOOD_DONOR',
    'CAREGIVER',
    'PATIENT',
    'SICKLER',
    'HOSPITAL',
    'CLINIC',
    'HEALTHCARE_STAFF',
    'ORGANIZATION',
  };

  /// Single unambiguous destination, or `null` when the session spans multiple
  /// contexts and must be resolved through the "Continue as" screen.
  static AppContext? resolve({
    required List<String> roles,
    String? doctorVerificationStatus,
  }) {
    final contexts = contextsFor(
      roles: roles,
      doctorVerificationStatus: doctorVerificationStatus,
    );
    return contexts.length == 1 ? contexts.first : null;
  }
}