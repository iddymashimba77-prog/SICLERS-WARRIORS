import 'package:flutter/material.dart';

/// Sickler's Warriors — official design tokens (FRONTEND-1).
///
/// Single source of truth for the product palette. Feature screens, global
/// widgets and the theme read these tokens only; colours are never scattered
/// as literals inside widgets.
///
/// Semantic usage (approved "frontend-1" direction):
/// - **Navy** `#0B1F3D` — top bars, important headings, navigation, selected
///   navigation, strong text.
/// - **Blue** `#1B5FAE` — primary buttons, links, progress, interactive
///   elements, selected states.
/// - **Red** `#C81E3A` — RESERVED for emergency / SOS / blood / critical
///   health states and important donation actions. Never a primary surface.
/// - Neutrals + success green + warning amber for supportive states.
///
/// Legacy aliases (`primary`, `secondary`, `info`, `success`, ...) are kept so
/// existing feature code stays readable while migrating to the token names.
@immutable
class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------- brands
  /// Primary Navy — top bars, headings, navigation. (Official token.)
  static const Color navy = Color(0xFF0B1F3D);

  /// Primary Blue — primary actions, links, selection. (Official token.)
  static const Color blue = Color(0xFF1B5FAE);

  /// Medical / emergency red — SOS, blood, critical states only.
  static const Color emergency = Color(0xFFC81E3A);

  /// Emergency red tint used behind emergency icons/indicators.
  static const Color emergencyContainer = Color(0xFFFCEBEE);

  /// Deep brand red — primary headline red of the official brand palette.
  static const Color darkRed = Color(0xFF9F1530);

  /// Light brand red tint — hero/news/tagged surfaces.
  static const Color lightRed = Color(0xFFFDECEF);

  /// Light brand blue tint — informational/tagged surfaces.
  static const Color lightBlue = Color(0xFFEAF3FB);

  // -------------------------------------------------------------- surfaces
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF8FAFD);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // ----------------------------------------------------------------- states
  /// Accessible success green (recorded / healthy / confirmed).
  static const Color success = Color(0xFF16803C);

  /// Accessible warning amber/orange.
  static const Color warning = Color(0xFFB7791F);

  /// Light informational blue accent.
  static const Color info = Color(0xFF1B5FAE);

  // ------------------------------------------------------------------- text
  static const Color textPrimary = Color(0xFF172033);
  static const Color textOnDark = Color(0xFFF4F7FB);
  static const Color textSecondary = Color(0xFF667085);
  static const Color textMuted = Color(0xFF8A97A8);
  static const Color textDisabled = Color(0xFFB6C1CF);
  static const Color textOnBlue = Color(0xFFFFFFFF);
  static const Color textOnEmergency = Color(0xFFFFFFFF);

  // ----------------------------------------------------------------- borders
  static const Color border = Color(0xFFE4E7EC);
  static const Color borderSubtle = Color(0xFFEDF1F6);
  static const Color divider = Color(0xFFE9EEF4);

  // --------------------------------------------------------- legacy aliases
  // Brand blue used to be the accent; these names are kept for compatibility
  // with pre-FRONTEND-1 screens. Migrate to `navy`/`blue` going forward.
  static const Color primary = navy;
  static const Color secondary = blue;
}