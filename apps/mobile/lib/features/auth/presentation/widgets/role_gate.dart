/// Sickler's Warriors — role-aware frontend foundation (FRONTEND-1).
///
/// Roles are assigned by the backend from the authenticated session and are
/// only a *routing* hint here. The backend remains the security authority:
/// the frontend never relies on role checks for authorization.
library;

import 'package:flutter/widgets.dart';

/// Known backend role codes returned on login / refresh.
abstract final class AppRoles {
  static const String patient = 'PATIENT';
  static const String sickler = 'SICKLER';
  static const String doctor = 'DOCTOR';
  static const String bloodDonor = 'BLOOD_DONOR';
  static const String caregiver = 'CAREGIVER';
  static const String admin = 'ADMIN';
  static const String superAdmin = 'SUPER_ADMIN';

  /// Any role that identifies a patient-facing account with health content.
  static bool isPatient(List<String> roles) =>
      roles.contains(patient) || roles.contains(sickler);

  static bool isAdminRole(List<String> roles) =>
      roles.contains(admin) || roles.contains(superAdmin);

  static bool isDoctor(List<String> roles) => roles.contains(doctor);
}

/// Chooses the post-login route for a session from its backend-assigned roles
/// (FRONTEND-3).
///
/// Role priority: admin/super admin → doctor → blood donor → caregiver →
/// patient. This is a routing hint only; every destination performs its own
/// backend-authorized calls. The returned route is a named app route for an
/// existing shell; [MainShell] is the documented default for patients.
String primaryShellRoute(List<String> roles) {
  if (roles.contains(AppRoles.superAdmin) || roles.contains(AppRoles.admin)) {
    return '/admin';
  }
  if (roles.contains(AppRoles.doctor)) return '/doctor-shell';
  if (roles.contains(AppRoles.bloodDonor)) return '/donor-shell';
  if (roles.contains(AppRoles.caregiver)) return '/caregiver-shell';
  return '/shell';
}

/// Gate that shows `child` for allowed roles and `fallback` otherwise.
///
/// Presentation-only. All real authorization continues to be enforced by the
/// backend API.
class RoleGate extends StatelessWidget {
  const RoleGate({
    super.key,
    required this.roles,
    required this.allow,
    required this.child,
    this.fallback = const SizedBox.shrink(),
  });

  /// Role codes from the authenticated session (AuthController.roles).
  final List<String> roles;

  /// Role codes permitted to see [child].
  final Set<String> allow;

  final Widget child;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final allowed = roles.any(allow.contains);
    return allowed ? child : fallback;
  }
}