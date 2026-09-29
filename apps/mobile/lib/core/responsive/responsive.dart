import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Sickler's Warriors — responsive breakpoint strategy (FRONTEND-1).
///
/// Layouts depend on width, not hard-coded device names. Breakpoints follow
/// the Material density buckets plus an extra large-desktop tier.
enum AppScreenSize {
  /// < 600 px — small & large phones.
  compact,

  /// 600 – 1023 px — folded/tablets and small windows.
  medium,

  /// 1024 – 1439 px — desktops and wide tablets.
  expanded,

  /// ≥ 1440 px — large desktop / wide monitors.
  large,
}

abstract final class AppLayout {
  /// < 600 px.
  static const double compact = 600;

  /// < 1024 px.
  static const double medium = 1024;

  /// < 1440 px.
  static const double expanded = 1440;

  static AppScreenSize screenSizeOf(BoxConstraints constraints) {
    final w = constraints.maxWidth;
    if (w < compact) return AppScreenSize.compact;
    if (w < medium) return AppScreenSize.medium;
    if (w < expanded) return AppScreenSize.expanded;
    return AppScreenSize.large;
  }

  static AppScreenSize screenSizeOfContext(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return screenSizeOf(
      BoxConstraints(maxWidth: size.width, maxHeight: size.height),
    );
  }

  static bool isCompact(BuildContext context) =>
      screenSizeOfContext(context) == AppScreenSize.compact;

  static bool isCompactConstraints(BoxConstraints constraints) =>
      screenSizeOf(constraints) == AppScreenSize.compact;

  /// Grid columns per size tier (dashboard grids etc.).
  static int columnCount(AppScreenSize size) {
    switch (size) {
      case AppScreenSize.compact:
        return 2;
      case AppScreenSize.medium:
        return 3;
      case AppScreenSize.expanded:
        return 4;
      case AppScreenSize.large:
        return 6;
    }
  }

  /// Content horizontal padding for the current width.
  static double edgePadding(AppScreenSize size) =>
      size == AppScreenSize.compact ? AppSpacing.screenEdge : AppSpacing.xl;

  /// Whether the shell should use a bottom navigation bar (mobile style).
  static bool useBottomNavigation(BoxConstraints constraints) =>
      isCompactConstraints(constraints);

  /// Whether the navigation rail may use extended labels.
  static bool showRailLabels(BoxConstraints constraints) =>
      !isCompactConstraints(constraints);
}

/// Builder that rebuilds its subtree when the screen size tier changes.
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, AppScreenSize size) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = AppLayout.screenSizeOf(constraints);
        return builder(context, size);
      },
    );
  }
}

/// Centers content in a max-width column on wide screens; full width on phones.
class ContentColumn extends StatelessWidget {
  const ContentColumn({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth = AppSpacing.contentMaxWidth,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }
}