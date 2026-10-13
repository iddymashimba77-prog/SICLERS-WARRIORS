import 'package:flutter/widgets.dart';

import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/widgets/session_scope.dart';

/// Routes that require a signed-in session (server-verified once inside).
///
/// The public home / header never push these raw for anonymous visitors:
/// [goTo] routes them to the sign-in flow instead, so public pages stay
/// accessible and protected surfaces never render a broken, token-less state.
const List<String> _protectedExact = [
  '/health',
  '/health/timeline',
  '/medication',
  '/records',
  '/medical',
  '/clinic',
  '/blood-donation',
  '/donor-home',
  '/donor-shell',
  '/doctor-shell',
  '/doctor-medications',
  '/caregiver-shell',
  '/role-workspace',
  '/emergency',
  '/community',
  '/messages',
  // '/education' is intentionally NOT here: the backend serves only PUBLISHED
  // education to anonymous readers (EducationContentView is AllowAny), so
  // gating it sent signed-out visitors to the login wall for content they are
  // allowed to read. Authors still reach the create surface from their own
  // role dashboard, which is protected by role, not by this list.
  '/ai-assistant',
  '/donations',
  '/daktari',
  '/doctor-home',
  '/profile',
  '/notifications',
  '/change-password',
  // MainShell.routeName — the entry above used to read '/main-shell', which no
  // class declares, so the session wall never applied to the real shell route.
  '/shell',
];

bool isProtectedRoute(String route) =>
    _protectedExact.contains(route) || route.startsWith('/admin');

/// True when the nearest session scope is signed in (non-subscribing read).
bool isSignedIn(BuildContext context) =>
    SessionScope.read(context)?.isAuthenticated ?? false;

/// Navigate to [route], honouring the session wall for protected
/// destinations: anonymous visitors are sent to sign in instead.
void goTo(BuildContext context, String route) {
  if (isProtectedRoute(route) && !isSignedIn(context)) {
    Navigator.of(context).pushNamed(LoginPage.routeName);
    return;
  }
  Navigator.of(context).pushNamed(route);
}