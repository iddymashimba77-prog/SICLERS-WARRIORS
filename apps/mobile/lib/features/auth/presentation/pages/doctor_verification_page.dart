import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../public/presentation/pages/public_home_page.dart';
import '../controllers/auth_controller.dart';
import '../widgets/session_scope.dart';

/// AUTH-2 — doctor verification status screen.
///
/// Surfaced for DOCTOR holders whose professional verification is not
/// APPROVED (PENDING / REJECTED / SUSPENDED / no registry row yet). The
/// clinical dashboard is reachable only after server-side approval; this
/// screen explains the status and keeps the account honest ("account type is
/// not verification").
class DoctorVerificationPage extends StatefulWidget {
  const DoctorVerificationPage({super.key, this.controller});

  static const String routeName = '/doctor-status';

  final AuthController? controller;

  @override
  State<DoctorVerificationPage> createState() => _DoctorVerificationPageState();
}

class _DoctorVerificationPageState extends State<DoctorVerificationPage> {
  AuthController get _controller =>
      widget.controller ?? SessionScope.controllerOf(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppLocalizations.of(context);
    final controller = _controller;
    final status = controller.doctorVerificationStatus ?? 'PENDING';

    final (titleKey, messageKey, icon, color) = switch (status) {
      'APPROVED' => (
          'auth.doctorStatus.approvedTitle',
          'auth.doctorStatus.approvedBody',
          Icons.verified_outlined,
          Colors.green,
        ),
      'REJECTED' => (
          'auth.doctorStatus.rejectedTitle',
          'auth.doctorStatus.rejectedBody',
          Icons.cancel_outlined,
          AppColors.emergency,
        ),
      'SUSPENDED' => (
          'auth.doctorStatus.suspendedTitle',
          'auth.doctorStatus.suspendedBody',
          Icons.pause_circle_outline,
          AppColors.emergency,
        ),
      _ => (
          'auth.doctorStatus.pendingTitle',
          'auth.doctorStatus.pendingBody',
          Icons.hourglass_top_outlined,
          AppColors.primary,
        ),
    };

    return Scaffold(
      appBar: AppBar(title: Text(s.tr('auth.doctorAccount'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Icon(icon, size: 72, color: color),
                const SizedBox(height: 16),
                Text(
                  s.tr(titleKey),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  s.tr(messageKey),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      PublicHomePage.routeName,
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.home_outlined),
                  label: Text(s.tr('auth.goToHome')),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await _controller.logout();
                    if (context.mounted) {
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        PublicHomePage.routeName,
                        (route) => false,
                      );
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: Text(AppStrings.signOut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}