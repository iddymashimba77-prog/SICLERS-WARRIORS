import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../shared/widgets/admin_shell.dart';
import '../../../auth/presentation/widgets/role_gate.dart';
import '../../../auth/presentation/widgets/session_scope.dart';

/// Restricted administration area (FRONTEND-1 foundation, fixed in FRONTEND-3).
///
/// Reads the authenticated session's roles instead of a hardcoded empty list,
/// so an ADMIN/SUPER_ADMIN session actually reaches the [AdminShell]. The
/// backend remains the authorization authority: every admin call is
/// permission-guarded server-side.
class AdminPanelPage extends StatelessWidget {
  const AdminPanelPage({super.key});

  static const String routeName = '/admin';

  @override
  Widget build(BuildContext context) {
    final roles = SessionScope.read(context)?.roles ?? const [];
    return RoleGate(
      roles: roles,
      allow: {AppRoles.admin, AppRoles.superAdmin},
      fallback: const _NoAccess(),
      child: const AdminShell(),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(tr('admin.restrictedArea'),
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                tr('admin.restrictedBody'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}