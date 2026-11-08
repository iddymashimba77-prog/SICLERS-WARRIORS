import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/theme/app_spacing.dart';

/// The three-step care journey shown at the bottom of the public mission page.
class CareJourneySection extends StatelessWidget {
  const CareJourneySection({super.key});

  static const _steps = <({String title, String body, IconData icon})>[
    (
      title: 'about.journeyStep1Title',
      body: 'about.journeyStep1Body',
      icon: Icons.person_add_alt_1_outlined,
    ),
    (
      title: 'about.journeyStep2Title',
      body: 'about.journeyStep2Body',
      icon: Icons.medical_services_outlined,
    ),
    (
      title: 'about.journeyStep3Title',
      body: 'about.journeyStep3Body',
      icon: Icons.monitor_heart_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppLocalizations.of(context);
    final wide = MediaQuery.of(context).size.width > 1024;
    return Container(
      color: theme.colorScheme.surface,
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.xxxl,
        horizontal: wide ? AppSpacing.xxxl : AppSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.contentMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.tr('about.journeyTitle'),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Text(
                  s.tr('about.journeySubtitle'),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.55,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900 ? 3 : 1;
                  final gap = AppSpacing.lg;
                  final width = columns == 1
                      ? constraints.maxWidth
                      : (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final (index, step) in _steps.indexed)
                        SizedBox(
                          width: width,
                          child: _JourneyCard(
                            index: index + 1,
                            icon: step.icon,
                            title: s.tr(step.title),
                            body: s.tr(step.body),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
  });

  final int index;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppShapes.large,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.lightBlue,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.blue, size: 23),
              ),
              const Spacer(),
              Text(
                index.toString().padLeft(2, '0'),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: AppColors.blue.withValues(alpha: .28),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
