/// App-level configuration constants for Sickler's Warriors.
///
/// The API base URL is the only backend touch-point here. It must NOT carry
/// secrets, tokens or PHI (§24). Backend addresses are environment-specific;
/// this file is the single override point for dev/staging/production.
library;

class AppConfig {
  AppConfig._();

  /// Backend API origin + version prefix. Trailing slash omitted.
  ///
  /// Defaults to the local Django dev server (see backend/config/urls.py).
  /// Override at build time (e.g. `--dart-define=API_BASE_URL=...`).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api',
  );
}