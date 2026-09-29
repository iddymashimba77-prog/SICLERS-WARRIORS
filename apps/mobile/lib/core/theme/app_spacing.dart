/// Sickler's Warriors — spacing scale (FRONTEND-1).
///
/// One predictable spacing scale for every screen. Use the named sizes instead
/// of arbitrary literals; combine with `gapH`/`gapW` helpers.
library;

import 'package:flutter/widgets.dart';

@immutable
class AppSpacing {
  const AppSpacing._();

  /// 2 px — tightest micro gutter.
  static const double xxs = 2;

  /// 4 px — icon-to-icon gutters, inner chip padding.
  static const double xs = 4;

  /// 8 px — small gaps between related elements.
  static const double sm = 8;

  /// 12 px — default between controls and labels.
  static const double md = 12;

  /// 16 px — default paragraph / card internal padding.
  static const double lg = 16;

  /// 24 px — section spacing.
  static const double xl = 24;

  /// 32 px — major section / screen breathing room.
  static const double xxl = 32;

  /// 48 px — screen top/bottom rhythm.
  static const double xxxl = 48;

  /// 64 px — large visual breathing room (hero, onboarding).
  static const double huge = 64;

  /// Mobile screen edge padding.
  static const double screenEdge = 16;

  /// Comfortable content max width on wide (desktop/web) layouts.
  static const double contentMaxWidth = 1200;
}

/// Horizontal gap helper — `gapW(AppSpacing.md)`.
SizedBox gapW(double width) => SizedBox(width: width);

/// Vertical gap helper — `gapH(AppSpacing.md)`.
SizedBox gapH(double height) => SizedBox(height: height);