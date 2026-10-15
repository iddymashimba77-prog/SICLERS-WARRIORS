import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_shapes.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/signup_page.dart';

/// Shared signed-out surface for guarded role screens.
///
/// Every protected surface used to fall back to a bare centred sentence, which
/// gave the user no title and no way forward except the system back gesture.
/// One branded gate — icon, honest message, sign-in and sign-up actions — keeps
/// the signed-out experience identical across patient, doctor, donor,
/// caregiver and public-feature screens.
class SignedOutGate extends StatelessWidget {
  const SignedOutGate({super.key, this.title, this.message});

  /// Screen name shown in the app bar; defaults to the product name.
  final String? title;

  /// Honest explanation of why the screen is closed (defaults to the shared
  /// signed-out copy so existing regression assertions keep holding).
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title ?? AppStrings.appName)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: AppShapes.large,
                  ),
                  child: Icon(
                    Icons.lock_outline,
                    size: 34,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  message ?? AppStrings.notSignedIn,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, LoginPage.routeName),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(200, 48),
                  ),
                  child: Text(AppStrings.login),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, SignupPage.routeName),
                  child: Text(AppStrings.register),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
