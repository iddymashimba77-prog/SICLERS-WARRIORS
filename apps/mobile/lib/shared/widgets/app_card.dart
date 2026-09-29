import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shapes.dart';
import '../../core/theme/app_spacing.dart';

/// Sickler's Warriors — base card (FRONTEND-1).
///
/// A calm, modern container: rounded corners, subtle border, very soft shadow,
/// comfortable padding. All specialised cards (StatCard, ActionCard, domain
/// cards) compose this so the surface language stays consistent.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.color,
    this.borderColor,
    this.alignment = Alignment.centerLeft,
  });

  /// Builds a card that reacts to taps (ripple + reduced motion fetch).
  const AppCard.action({
    super.key,
    required this.child,
    required this.onTap,
  })  : padding = const EdgeInsets.all(AppSpacing.lg),
        color = null,
        borderColor = null,
        alignment = Alignment.centerLeft;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color surface = color ?? scheme.surface;
    final BoxDecoration decoration = BoxDecoration(
      color: surface,
      borderRadius: AppShapes.card,
      border: Border.all(color: borderColor ?? scheme.outlineVariant),
      boxShadow: [
        BoxShadow(
          color: AppColors.navy.withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );

    final Widget content = Container(
      decoration: decoration,
      padding: padding,
      alignment: alignment,
      child: child,
    );

    if (onTap == null) return content;

    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppShapes.card,
          child: content,
        ),
      ),
    );
  }
}