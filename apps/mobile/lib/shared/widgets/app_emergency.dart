import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'app_card.dart';
import '../../core/theme/app_shapes.dart';

/// Sickler's Warriors — emergency visual language (FRONTEND-1).
///
/// Emergency actions are visually unmistakable: red token, distinct shape,
/// explicit confirmation. They must never be confused with normal buttons and
/// must not be triggered accidentally.

/// Reusable SOS / emergency action button.
///
/// Renders as a large, high-contrast red action labelled with the given
/// message. Requires a two-stage confirmation ([confirmLabel] dialog) before
/// invoking [onConfirmed], so it cannot be triggered by a single stray tap.
class SosButton extends StatelessWidget {
  const SosButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.confirmTitle,
    this.confirmMessage,
    this.confirmLabel,
    this.icon = Icons.sos,
    this.subtitle,
    this.expanded = true,
  });

  final String label;
  final VoidCallback onConfirmed;
  final String? confirmTitle;
  final String? confirmMessage;
  final String? confirmLabel;
  final IconData icon;
  final String? subtitle;
  final bool expanded;

  Future<void> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.emergency,
          size: 40,
        ),
        title: Text(confirmTitle ?? tr('sos.confirmTitle')),
        content: Text(confirmMessage ?? tr('sos.confirmMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emergency,
              foregroundColor: AppColors.textOnEmergency,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel ?? tr('sos.sendAlert')),
          ),
        ],
      ),
    );
    if (ok ?? false) onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget button = Material(
      color: AppColors.emergency,
      borderRadius: AppShapes.tile,
      elevation: 0,
      child: InkWell(
        onTap: () => _confirm(context),
        borderRadius: AppShapes.tile,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.textOnEmergency, size: 26),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.textOnEmergency,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textOnEmergency.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: '$label. Requires confirmation before sending.',
      child: button,
    );
  }
}

/// Emergency alert card — used to surface critical/emergency status with an
/// action. Purely a container; content/decisions come from the caller.
class EmergencyCard extends StatelessWidget {
  const EmergencyCard({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.medical_services_outlined,
    this.onTap,
    this.actionLabel,
  });

  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? onTap;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = dark ? theme.colorScheme.error : AppColors.emergency;
    return AppCard(
      onTap: onTap,
      color: dark
          ? AppColors.emergency.withValues(alpha: .16)
          : AppColors.emergencyContainer,
      borderColor: accent.withValues(alpha: 0.35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: dark ? AppColors.emergency.withValues(alpha: .85) : AppColors.emergency,
              borderRadius: AppShapes.tile,
            ),
            child: Icon(icon, color: AppColors.textOnEmergency, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  message,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurface),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    actionLabel!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}