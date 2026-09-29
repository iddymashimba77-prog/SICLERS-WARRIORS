import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_spacing.dart';

/// Secure medical-record surface (FRONTEND-3).
///
/// The backends does not expose a medical-records API yet, so this screen
/// shows an honest, consent-framed empty state — records are never fabricated
/// and never rendered without authorization.
class MedicalRecordsPage extends StatelessWidget {
  const MedicalRecordsPage({super.key});

  static const String routeName = '/records';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.healthRecords)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: AppColors.surface,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.folder_shared_outlined,
                        size: 56,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        AppStrings.recordsEmptyTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        AppStrings.recordsEmptyBody,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      AppStrings.recordsPrivacy,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.lg),
              Text(
                AppStrings.consentAndPrivacy.toUpperCase(),
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppStrings.consentBody,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}