/// Application configuration for Sickler's Warriors.
///
/// The API base URL is the single point that differs between run targets, so
/// it is resolved at runtime instead of being hard-coded:
///
/// * **Android emulator / tablet emulator** — the host machine's loopback is
///   reachable at `10.0.2.2`, so that is used (a physical Android device must
///   be pointed at the host's LAN IP via `--dart-define`, see below).
/// * **iOS simulator, iPad, desktop (Linux/macOS/Windows) and web** — the host
///   loopback is simply `localhost`.
///
/// For a **physical device** on the same network, or any non-default target,
/// pass the address at build/run time:
///
/// ```
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api
/// ```
///
/// No secrets are ever stored here; the value is public.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

class AppConfig {
  AppConfig._();

  /// Compile-time override (wins over the platform default when non-empty).
  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// Base URL including the `/api` prefix, e.g. `http://localhost:8000/api`.
  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    const String kLiveApi = 'https://sicklers-api.onrender.com/api';
    // Default to live API in release builds; keep emulator-friendly defaults in dev
    if (kReleaseMode) {
      return kLiveApi;
    }
    if (!kIsWeb && Platform.isAndroid) {
      // Android emulator/tablet maps the host loopback to 10.0.2.2.
      return 'http://10.0.2.2:8000/api';
    }
    return 'http://localhost:8000/api';
  }
}
