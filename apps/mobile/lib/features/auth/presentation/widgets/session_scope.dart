import 'package:flutter/widgets.dart';

import '../../data/auth_repository.dart';
import '../../data/token_store.dart';
import '../controllers/auth_controller.dart';

/// App-wide session provider (FRONTEND-2).
///
/// A single [AuthController] is created once at the app root and shared by
/// every screen through [SessionScope]. Without this, each page builds its own
/// controller with an ephemeral store, so tokens never survive navigation and
/// the Home dashboard could never reach authenticated endpoints.
///
/// Screens read the nearest scope:
///
/// ```dart
/// final auth = SessionScope.controllerOf(context);
/// ```
///
/// Widget tests that pump a page directly (no scope) fall back to a private,
/// unauthenticated controller so signed-out empty states render without
/// touching the network.
class SessionScope extends InheritedNotifier<AuthController> {
  const SessionScope({
    super.key,
    required AuthController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Subscribing access — rebuilds this element when the session notifies.
  static AuthController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()?.notifier;

  /// Non-subscribing access for callbacks and one-shot reads.
  static AuthController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SessionScope>()?.notifier;

  /// Nearest session controller, or an unauthenticated fallback when no scope
  /// exists (standalone widget tests, isolated screens). The fallback is kept
  /// deliberately unsigned-in and shares no state with any logged-in session.
  static AuthController controllerOf(BuildContext context) =>
      maybeOf(context) ?? _fallback;

  static final AuthController _fallback = AuthController(
    repository: AuthRepository(tokenStore: EphemeralTokenStore()),
  );
}