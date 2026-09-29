import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Sickler's Warriors — centralized typography (FRONTEND-1).
///
/// Each named role maps onto the Material `TextTheme` applied by `AppTheme`,
/// so widgets either use `Theme.of(context).textTheme.*` or these named styles.
/// Sizes stay conservative for medical readability; line-height ≥ 1.4.
///
/// Colours are resolved per brightness so the same roles read correctly in
/// light and dark surfaces.
abstract final class AppTypography {

  /// Display — large, sparse hero numbers/titles (rarely used).
  static const TextStyle display = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
  );

  /// Headline — primary screen headings.
  static const TextStyle headline = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  /// Section/medium headline.
  static const TextStyle headlineSmall = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Title — card/joint section titles.
  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  /// Section title — uppercase micro headings above sections.
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.6,
  );

  /// Body — default reading text.
  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// Body medium — emphasised reading text.
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  /// Body small — supporting text.
  static const TextStyle bodySmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// Caption — labels, timestamps, secondary details.
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// Label — field labels, tab micro-labels.
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Button — button / link text.
  static const TextStyle button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.1,
  );

  /// Build the Material [TextTheme] consumed by [ThemeData].
  static TextTheme textTheme({Brightness brightness = Brightness.light}) {
    final Color primary =
        brightness == Brightness.light
            ? AppColors.textPrimary
            : AppColors.textOnDark.withValues(alpha: 0.92);
    final Color secondary =
        brightness == Brightness.light
            ? AppColors.textSecondary
            : AppColors.textOnDark.withValues(alpha: 0.72);

    return TextTheme(
      displayLarge: display.copyWith(color: primary),
      headlineLarge: headline.copyWith(color: primary),
      headlineMedium: headlineSmall.copyWith(color: primary),
      titleLarge: title.copyWith(color: primary),
      titleMedium: title.copyWith(color: primary),
      titleSmall: label.copyWith(color: primary),
      bodyLarge: body.copyWith(color: primary),
      bodyMedium: bodyMedium.copyWith(color: primary),
      bodySmall: bodySmall.copyWith(color: secondary),
      labelLarge: button.copyWith(color: primary),
      labelMedium: label.copyWith(color: secondary),
      labelSmall: sectionTitle.copyWith(color: secondary),
    );
  }

  /// Light text theme.
  static TextTheme get light => textTheme();

  /// Dark text theme.
  static TextTheme get dark => textTheme(brightness: Brightness.dark);
}