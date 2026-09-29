/// Legacy import path for the official color tokens.
///
/// FRONTEND-1 moved brand tokens to `core/theme/app_colors.dart` (single
/// source of truth). Older feature imports keep pointing here; this file only
/// re-exports the canonical tokens so nothing breaks.
library;

export '../theme/app_colors.dart';