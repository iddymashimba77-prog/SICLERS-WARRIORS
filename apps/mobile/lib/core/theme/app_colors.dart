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

  /// Light amber/warning tint — cautionary informational surfaces.
  static const Color lightAmber = Color(0xFFFFF7E6);

  /// Deeper navy stop used inside navy gradients.
  static const Color navyDeep = Color(0xFF0E2A4F);

  /// Accessible blue tint for text/icons on dark surfaces. Matches the dark
  /// theme primary so dark-mode accents share one token.
  static const Color blueOnDark = Color(0xFF8FBCF0);

  // ------------------------------------------------------- dark surfaces
  /// Logged-in dark shell background.
  static const Color darkSurfaceLowest = Color(0xFF0A111E);
  static const Color darkSurface = Color(0xFF0D1626);
  static const Color darkSurfaceLow = Color(0xFF111C2F);
  static const Color darkSurfaceContainer = Color(0xFF16223A);
  static const Color darkSurfaceHigh = Color(0xFF1B2945);
  static const Color darkSurfaceHighest = Color(0xFF213150);

  /// Logged-in dark app bar and hairline borders.
  static const Color darkAppBar = Color(0xFF0E1626);
  static const Color darkOutline = Color(0xFF33455F);
  static const Color darkOutlineVariant = Color(0xFF26364E);

  /// Logged-in dark text tones.
  static const Color darkText = Color(0xFFE6EDF6);
  static const Color darkTextMuted = Color(0xFF9FB0C5);

  // ------------------------------------------------- public home (reference)
  /// Public home dark gradient — a softened, homepage-only navy family. The
  /// logged-in `navy` / `darkSurface*` tokens stay unchanged.
  static const Color homeNavyTop = Color(0xFF112543);
  static const Color homeNavyMid = Color(0xFF121C2D);
  static const Color homeDarkBottom = Color(0xFF172236);
  static const Color homeBlueBottom = blue;

  /// Softened homepage card, border and muted-text tones.
  static const Color homeDarkCard = Color(0xFF1C2A3F);
  static const Color homeDarkCardHover = Color(0xFF223049);
  static const Color homeDarkOutline = Color(0xFF3A4B61);
  static const Color homeDarkOutlineVariant = Color(0xFF2C3B51);
  static const Color homeDarkTextMuted = Color(0xFFA5B3C5);

  /// Softened dark surface behind the public-home phone preview.
  static const Color homePhoneScreen = homeNavyMid;

  /// Brand red for SOS / primary public actions.
  static const Color homeRed = emergency;
  static const Color homeRedDeep = darkRed;
  static const Color homeRedSoft = Color(0xFFF26D7D);

  /// Brand blue accents for public-home light icons and dark-surface glows.
  static const Color homeAccentBlue = blue;
  static const Color homeAccentBlueSoft = blueOnDark;
  static const Color homeTextSoft = Color(0xFFD6E4F5);

  /// Ink and screen tones for the light-adapted public home / phone preview.
  static const Color homeInk = navy;
  static const Color homeInkMuted = textSecondary;
  static const Color homeScreen = surface;
  static const Color homeLightTop = surface;
  static const Color homeLightMid = lightBlue;
  static const Color homeLightBottom = Color(0xFFD9E6F4);

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
  /// Divider / hairline drawn on dark (navy) surfaces.
  static const Color dividerOnDark = Color(0x33FFFFFF);

  // --------------------------------------------------------- legacy aliases
  // Brand blue used to be the accent; these names are kept for compatibility
  // with pre-FRONTEND-1 screens. Migrate to `navy`/`blue` going forward.
  static const Color primary = navy;
  static const Color secondary = blue;
}