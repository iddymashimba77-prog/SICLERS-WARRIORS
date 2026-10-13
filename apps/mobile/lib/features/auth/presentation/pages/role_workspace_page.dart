import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../public/presentation/pages/public_home_page.dart';
import '../widgets/session_scope.dart';

/// Unknown / admin-created role workspace (REQ-4 role pages).
///
/// When the server asserts a role this build does not have a dedicated shell
/// for (for example a role provisioned later through the admin panel), the
/// session resolves here instead of silently landing in the patient shell. The
/// page acknowledges the real, server-granted role + permission codes — it
/// never fabricates capabilities.
class RoleWorkspacePage extends StatelessWidget {
  const RoleWorkspacePage({super.key});

  static const String routeName = '/role-workspace';

  @override
  Widget build(BuildContext context) {
    final controller = SessionScope.controllerOf(context);
    final roleCodes = [...controller.roles]..sort();
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.roleWorkspace)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(
              Icons.workspaces_outline,
              size: 64,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.roleWorkspaceHeading,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.roleWorkspaceBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            for (final role in roleCodes)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: AppShapes.card,
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.badge_outlined,
                    color: AppColors.primary,
                  ),
                  title: Text(role),
                  subtitle: const Text(AppStrings.roleGranted),
                  trailing: const Icon(Icons.check_circle_outline),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              AppStrings.roleWorkspacePermissions.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 8),
            if (controller.permissions.isEmpty)
              const Text(AppStrings.noPermissionsGranted)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in controller.permissions)
                    Chip(
                      avatar: const Icon(Icons.key_outlined, size: 14),
                      label: Text(p),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () async {
                await controller.logout();
                if (!context.mounted) return;
                Navigator.of(context).pushNamedAndRemoveUntil(
                  PublicHomePage.routeName,
                  (route) => false,
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text(AppStrings.signOut),
            ),
          ],
        ),
      ),
    );
  }
}