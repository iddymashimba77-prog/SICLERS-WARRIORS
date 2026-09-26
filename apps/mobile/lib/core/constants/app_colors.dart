import 'package:flutter/material.dart';

/// Brand color palette for Sickler's Warriors.
///
/// Approved brand tokens (Stage 3, mobile-ui-ux-design §3 / admin-web-ui-ux §3):
///
/// - **Primary — Dark Blue** `#0D47A1` — brand, app bars, primary buttons.
/// - **Secondary — Blue** `#1976D2` — links, secondary controls, info accent.
/// - **Emergency — Red** `#C62828` — RESERVED for emergency, blood-related
///   alerts, critical and important warnings only. Never a primary surface.
/// - Neutrals (white / greys) for surfaces, text and borders.
///
/// Red is deliberately de-emphasised from the 3.4 scaffold (which used red as
/// the brand primary); per the approved 3.6/3.7 direction red is now an
/// emergency-only token and Dark Blue is the brand primary.
class AppColors {
  AppColors._();

  /// Primary brand colour — Dark Blue (approved brand token).
  static const Color primary = Color(0xFF0D47A1);

  /// Secondary / accent — Blue (approved brand token).
  static const Color secondary = Color(0xFF1976D2);

  /// Emergency / danger — Red. Emergency, blood-related alerts and critical
  /// states only (approved token; not a general surface colour).
  static const Color emergency = Color(0xFFC62828);

  /// Soothing medical teal for positive / healthy states.
  static const Color success = Color(0xFF00897B);

  /// Information / links.
  static const Color info = Color(0xFF1565C0);

  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
}
