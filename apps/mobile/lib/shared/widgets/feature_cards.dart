import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'app_card.dart';

/// Sickler's Warriors — domain card variants (FRONTEND-1).
///
/// Thin, reusable compositions over [AppCard] for recurring domain surfaces:
/// medication, appointments, education, donations, blood. These exist to give
/// later feature stages one consistent card vocabulary; they do not implement
/// any feature behaviour.

/// Medication card — name + strength + status without dosing logic here.
class MedicationCard extends StatelessWidget {
  const MedicationCard({
    super.key,
    required this.title,
    this.subtitle,
    this.statusLabel,
    this.statusTone = BadgeToneStatus.neutral,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? statusLabel;
  final BadgeToneStatus statusTone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color accent = switch (statusTone) {
      BadgeToneStatus.success => AppColors.success,
      BadgeToneStatus.warning => AppColors.warning,
      BadgeToneStatus.emergency => AppColors.emergency,
      BadgeToneStatus.neutral => AppColors.blue,
    };
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.medication_outlined, color: accent, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (statusLabel != null)
            Text(
              statusLabel!,
              style: theme.textTheme.labelMedium?.copyWith(color: accent),
            ),
        ],
      ),
    );
  }
}

enum BadgeToneStatus { neutral, success, warning, emergency }

/// Appointment card — time + title + location line.
class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.timeLabel,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final String timeLabel;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              timeLabel,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.blue,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Education card — topic + source/date line.
class EducationCard extends StatelessWidget {
  const EducationCard({
    super.key,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.school_outlined, color: AppColors.blue),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
    );
  }
}

/// Donation card — amount + campaign/status.
class DonationCard extends StatelessWidget {
  const DonationCard({
    super.key,
    required this.title,
    required this.amount,
    this.subtitle,
    this.statusLabel,
    this.onTap,
  });

  final String title;
  final String amount;
  final String? subtitle;
  final String? statusLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.favorite_outline,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (statusLabel != null)
                Text(statusLabel!, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

/// Blood card — blood-group leading marker + request/donor line.
class BloodCard extends StatelessWidget {
  const BloodCard({
    super.key,
    required this.title,
    this.subtitle,
    this.groupLabel,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? groupLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.emergency.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              groupLabel ?? 'B',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.emergency,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}