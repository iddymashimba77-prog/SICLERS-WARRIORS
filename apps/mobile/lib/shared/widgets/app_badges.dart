import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_shapes.dart';

/// Sickler's Warriors — badge / status pill (FRONTEND-1).
///
/// Status must never be communicated by colour alone: every badge includes a
/// semantic icon + text label so colour-blind users get the same information.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = BadgeTone.neutral,
    this.icon,
    this.compact = false,
  });

  final String label;
  final BadgeTone tone;
  final IconData? icon;
  final bool compact;

  Color get _accent => switch (tone) {
        BadgeTone.neutral => AppColors.textMuted,
        BadgeTone.info => AppColors.blue,
        BadgeTone.success => AppColors.success,
        BadgeTone.warning => AppColors.warning,
        BadgeTone.emergency => AppColors.emergency,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color fg = _accent;
    final Color bg = _accent.withValues(alpha: 0.1);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? AppSpacing.xs : 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppShapes.pill,
        border: Border.all(color: _accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              style: (compact
                      ? theme.textTheme.labelSmall
                      : theme.textTheme.labelMedium)
                  ?.copyWith(color: fg, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

enum BadgeTone { neutral, info, success, warning, emergency }

/// Simple filter chip that follows the theme.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      avatar: icon == null
          ? null
          : Icon(icon, size: 16, color: selected ? scheme.primary : null),
      showCheckmark: false,
      selectedColor: scheme.secondaryContainer,
      checkmarkColor: scheme.primary,
    );
  }
}