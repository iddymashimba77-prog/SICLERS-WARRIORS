/// Sickler's Warriors — dashboard component foundation (FRONTEND-1).
///
/// Reusable structures the patient Home dashboard (FRONTEND-2) will compose:
/// sections, stat cards, quick actions, health summaries, progress, timeline,
/// alerts and recommendations. These are building blocks only — the full
/// Home dashboard is intentionally NOT built in FRONTEND-1.
library;

import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'app_card.dart';

/// Section header — micro title + optional action row above a dashboard block.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xl,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall,
            ),
          ),
          if (trailing != null) trailing!,
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Stat card — a prominent number with label and optional icon/trend.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent = AppColors.blue,
    this.trendLabel,
    this.trendUp = true,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color accent;
  final String? trendLabel;
  final bool trendUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: accent),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(value, style: theme.textTheme.headlineLarge),
          if (trendLabel != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(
                  trendUp ? Icons.trending_up : Icons.trending_down,
                  size: 16,
                  color: trendUp ? AppColors.success : AppColors.emergency,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    trendLabel!,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Grid of [StatCard]s that adapts columns to screen width.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<StatCard> children;

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, size) {
        final columns = size == AppScreenSize.compact ? 2 : 4;
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final spacing = AppSpacing.md;
            final itemW = (width - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final c in children) SizedBox(width: itemW, child: c),
              ],
            );
          },
        );
      },
    );
  }
}

/// Quick action — compact tappable icon tile.
class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = AppColors.blue,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Adaptive grid of [QuickAction]s.
class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key, required this.actions});

  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, size) {
        if (size == AppScreenSize.compact) {
          const cols = 4;
          final width = MediaQuery.sizeOf(context).width - AppSpacing.screenEdge * 2;
          final itemW = (width - AppSpacing.sm * (cols - 1)) / cols;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final a in actions) SizedBox(width: itemW, child: a),
            ],
          );
        }
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final a in actions) SizedBox(width: 140, child: a),
          ],
        );
      },
    );
  }
}

/// Health summary card — labels a primary health/status figure.
class HealthSummaryCard extends StatelessWidget {
  const HealthSummaryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.value,
    this.accent = AppColors.success,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 26),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (value != null)
            Text(value!, style: theme.textTheme.titleLarge),
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ],
      ),
    );
  }
}

/// Progress card — labelled linear progress with a value.
class ProgressCard extends StatelessWidget {
  const ProgressCard({
    super.key,
    required this.label,
    required this.value,
    this.max = 100,
    this.icon,
    this.accent = AppColors.blue,
    this.caption,
  });

  final String label;
  final double value;
  final double max;
  final IconData? icon;
  final Color accent;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (value / max).clamp(0.0, 1.0);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(label, style: theme.textTheme.labelMedium),
              ),
              Text(
                '${(pct * 100).round()}%',
                style: theme.textTheme.labelMedium?.copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              color: accent,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(caption!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Timeline item — a single row in a health/activity timeline.
class TimelineItem extends StatelessWidget {
  const TimelineItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.time,
    this.icon = Icons.fiber_manual_record,
    this.accent = AppColors.blue,
  });

  final String title;
  final String subtitle;
  final String time;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: accent),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(time, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Alert card — noteworthy but non-emergency warning (medical safety copy).
class AlertCard extends StatelessWidget {
  const AlertCard({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
    this.tone = AlertTone.info,
    this.onTap,
    this.actionLabel,
  });

  final String title;
  final String message;
  final IconData icon;
  final AlertTone tone;
  final VoidCallback? onTap;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = switch (tone) {
      AlertTone.info => AppColors.blue,
      AlertTone.success => AppColors.success,
      AlertTone.warning => AppColors.warning,
      AlertTone.emergency => AppColors.emergency,
    };
    final bg = accent.withValues(alpha: 0.08);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(message, style: theme.textTheme.bodySmall),
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

/// Recommendation card — education/care suggestion (not a diagnosis).
class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.title,
    required this.body,
    this.onTap,
    this.icon = Icons.school_outlined,
  });

  final String title;
  final String body;
  final VoidCallback? onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.blue, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum AlertTone { info, success, warning, emergency }