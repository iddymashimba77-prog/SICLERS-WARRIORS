/// App asset paths for Sickler's Warriors.
///
/// Single source of truth for bundled asset references (brand art).
/// Everything resolves relative to the Flutter `assets/` directory declared
/// in `pubspec.yaml`.
library;

class AppAssets {
  AppAssets._();

  /// Official brand logo (see `assets/brand/sicklers_warriors_logo.png`).
  ///
  /// The file is a build-time placeholder until the final approved artwork is
  /// dropped in at this exact path — runtime consumers render a branded
  /// wordmark fallback if the bytes are ever missing (`AppLogo`).
  static const String brandLogo = 'assets/brand/sicklers_warriors_logo.png';
}