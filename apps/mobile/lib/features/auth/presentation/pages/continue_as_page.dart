import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../widgets/session_router.dart';
import '../widgets/session_scope.dart';
import '../../../../core/theme/app_shapes.dart';

/// AUTH-2 — multi-role post-auth context selector ("Continue as").
///
/// Shown only after a successful login/startup when the server reports more
/// than one usable context (e.g. PATIENT + BLOOD_DONOR). No role is silently
/// dropped: the caller routes through this screen whenever the session spans
/// multiple contexts. Contexts come from the server-authenticated session.
class ContinueAsPage extends StatelessWidget {
  const ContinueAsPage({super.key});

  static const String routeName = '/continue-as';

  @override
  Widget build(BuildContext context) {
    final controller = SessionScope.controllerOf(context);
    final contexts = SessionRouter.contextsFor(
      roles: controller.roles,
      doctorVerificationStatus: controller.doctorVerificationStatus,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Continue as')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.account_circle_outlined,
                    size: 64, color: AppColors.primary),
                const SizedBox(height: 16),
                Text(
                  'Which experience do you want to open?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your account has access to several roles. '
                  'Switching roles is available any time in your profile.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),
                for (final ctx in contexts) ...[
                  _ContextOption(
                    context_: ctx,
                    onTap: () {
                      Navigator.of(context).pushReplacementNamed(ctx.route);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextOption extends StatelessWidget {
  const _ContextOption({required this.context_, required this.onTap});

  final AppContext context_;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppShapes.card,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          child: Icon(context_.icon, color: AppColors.primary),
        ),
        title: Text(context_.title),
        subtitle: Text(context_.subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}