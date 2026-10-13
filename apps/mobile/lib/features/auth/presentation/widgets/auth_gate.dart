import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_logo.dart';
import '../../../admin/presentation/pages/admin_panel_page.dart';
import '../../../blood_donation/presentation/pages/donor_shell.dart';
import '../../../caregiver/presentation/pages/caregiver_shell.dart';
import '../../../doctor/presentation/pages/doctor_shell.dart';
import '../../../public/presentation/pages/public_home_page.dart';
import '../../../../shared/widgets/main_shell.dart';
import '../controllers/auth_controller.dart';
import '../pages/continue_as_page.dart';
import '../pages/doctor_verification_page.dart';
import '../pages/organization_verification_page.dart';
import '../pages/role_workspace_page.dart';
import '../../domain/auth_types.dart';
import 'session_router.dart';
import 'session_scope.dart';

/// AUTH-2 — cold-start gate.
///
/// Renders the splash while the session is probing/validating
/// (INITIALIZING), then either a role-aware experience (AUTHENTICATED) or the
/// Public Home (UNAUTHENTICATED). A stored-but-invalid session never opens a
/// shell: /me failure resolves to Public Home (tokens are cleared on 401).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  static const String routeName = '/gate';

  @override
  Widget build(BuildContext context) {
    final controller = SessionScope.controllerOf(context);

    switch (controller.status) {
      case AuthStatus.initializing:
      case AuthStatus.loggingOut:
        return const _StartupSplash();
      case AuthStatus.unauthenticated:
      case AuthStatus.tokenExpired:
        return const PublicHomePage();
      case AuthStatus.authenticated:
      case AuthStatus.authError:
        if (!controller.isAuthenticated) return const PublicHomePage();
        return SessionRouterView(controller: controller);
      case AuthStatus.authenticating:
        return const PublicHomePage();
    }
  }
}

class _StartupSplash extends StatelessWidget {
  const _StartupSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBrand(markHeight: 64, showSubtitle: true),
            SizedBox(height: 24),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resolves the single role-aware destination for an authenticated session,
/// or the "Continue as" selection screen when the session spans many contexts.
class SessionRouterView extends StatelessWidget {
  const SessionRouterView({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    final resolved = SessionRouter.resolve(
      roles: controller.roles,
      doctorVerificationStatus: controller.doctorVerificationStatus,
    );
    if (resolved == null) {
      return const ContinueAsPage();
    }
    return _shellFor(context, resolved.route, controller: controller);
  }

  /// Maps the resolved themed route onto its widget. Shells are composed here
  /// so the cold-start gate and the named-route table agree on one surface.
  static Widget _shellFor(
    BuildContext context,
    String route, {
    required AuthController controller,
  }) {
    switch (route) {
      case '/admin':
        return const AdminPanelPage();
      case '/doctor-shell':
        return const DoctorShell();
      case '/donor-shell':
        return const DonorShell();
      case '/caregiver-shell':
        return const CaregiverShell();
      case '/doctor-status':
        return const DoctorVerificationPage();
      case '/org-status':
        return const OrganizationVerificationPage();
      case '/role-workspace':
        return const RoleWorkspacePage();
      case '/shell':
      default:
        return const MainShell();
    }
  }
}