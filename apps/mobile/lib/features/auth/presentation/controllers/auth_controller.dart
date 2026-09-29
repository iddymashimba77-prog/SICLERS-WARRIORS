import 'package:flutter/foundation.dart';

import '../../domain/auth_types.dart';
import '../../data/auth_repository.dart';

/// App-wide authentication state (FRONTEND-2 / AUTH-2).
///
/// State model (AUTH-2):
///   initializing   → cold start, session store probed + /me validation
///   unauthenticated→ no session (or invalid); public routes only
///   authenticating → a login/register/signout is in flight
///   authenticated  → valid session; role-aware routing may begin
///   tokenExpired   → session present but refresh failed; re-auth required
///   loggingOut     → sign-out in flight
///   authError      → last operation failed; [lastError] explains it
///
/// Verification is server-asserted only: [isVerifiedDoctor],
/// [doctorVerificationStatus] and [facility] are read from /auth/me + login,
/// never inferred from a client-chosen account type.
class AuthController extends ChangeNotifier {
  AuthController({required AuthRepository repository})
      : _repository = repository;

  final AuthRepository _repository;

  AuthStatus _status = AuthStatus.initializing;
  AuthStatus get status => _status;

  String? _accessToken;
  String? get accessToken => _accessToken;

  String? _refreshToken;
  String? get refreshToken => _refreshToken;

  String? _email;
  String? get email => _email;

  String? _firstName;
  String? get firstName => _firstName;

  String? _lastName;
  String? get lastName => _lastName;

  String? _accountStatus;
  String? get accountStatus => _accountStatus;

  bool _isVerifiedDoctor = false;
  bool get isVerifiedDoctor => _isVerifiedDoctor;

  String? _doctorVerificationStatus;
  String? get doctorVerificationStatus => _doctorVerificationStatus;

  Map<String, dynamic>? _facility;
  Map<String, dynamic>? get facility => _facility;

  bool _emailVerified = false;
  bool get emailVerified => _emailVerified;

  /// Best available display name for personalised surfaces.
  String? get displayName {
    final name = [_firstName, _lastName]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' ')
        .trim();
    return name.isEmpty ? null : name;
  }

  List<String> _roles = const [];
  List<String> get roles => _roles;

  /// Server-verified permission codes (ADMIN-3) — the same source-of-truth the
  /// backend gates on. Used by the admin shell to hide unauthorized sections;
  /// every mutation is still re-enforced server-side.
  List<String> _permissions = const [];
  List<String> get permissions => _permissions;

  AuthException? _lastError;
  AuthException? get lastError => _lastError;

  bool get isAuthenticated =>
      _status == AuthStatus.authenticated ||
      (_status == AuthStatus.authError && _accessToken != null);

  bool get isSendableEmail =>
      _status == AuthStatus.tokenExpired && _accessToken != null;

  bool _sessionBusy = false;
  bool get sessionBusy => _sessionBusy;

  void _resetIdentity() {
    _accessToken = null;
    _refreshToken = null;
    _email = null;
    _firstName = null;
    _lastName = null;
    _accountStatus = null;
    _isVerifiedDoctor = false;
    _doctorVerificationStatus = null;
    _facility = null;
    _emailVerified = false;
    _roles = const [];
    _permissions = const [];
  }

  void _applySession(AuthSessionOutcome outcome) {
    _email = outcome.email ?? _email;
    _firstName = outcome.firstName ?? _firstName;
    _lastName = outcome.lastName ?? _lastName;
    _accountStatus = outcome.accountStatus ?? _accountStatus;
    _isVerifiedDoctor = outcome.isVerifiedDoctor;
    _doctorVerificationStatus = outcome.doctorVerificationStatus;
    if (outcome.facility != null) _facility = outcome.facility;
    _emailVerified =
        outcome.accountStatus == 'ACTIVE' || outcome.emailVerificationPending == false;
    if (outcome.roles.isNotEmpty) _roles = outcome.roles;
    if (outcome.permissions.isNotEmpty) _permissions = outcome.permissions;
  }

  /// Cold-start session restore: probe the token store, then validate against
  /// /auth/me so a stored but dead/invalid session never reaches the shells.
  ///
  /// * No token            → unauthenticated (Public Home).
  /// * /me ACTIVE/PENDING  → authenticated with the server identity.
  /// * /me 401             → token cleared; unauthenticated.
  /// * Offline/timeout     → unauthenticated (Public Home) but tokens are kept
  ///                         so a later launch can retry silently.
  Future<void> restoreSession() async {
    _status = AuthStatus.initializing;
    notifyListeners();
    final access = await _repository.tokenStore.readAccess();
    if (access == null) {
      _resetIdentity();
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    _accessToken = access;
    try {
      final outcome = await _repository.me(access: access);
      _applySession(outcome);
      if (outcome.accountStatus == 'ACTIVE' ||
          outcome.accountStatus == 'PENDING_VERIFICATION') {
        _lastError = null;
        _status = AuthStatus.authenticated;
      } else {
        // SUSPENDED/DISABLED/DEACTIVATED — no session.
        await _repository.tokenStore.clear();
        _resetIdentity();
        _status = AuthStatus.unauthenticated;
      }
    } on AuthException catch (e) {
      _lastError = e;
      if (e.statusCode == 401 || e.code == 'TOKEN_EXPIRED') {
        await _repository.tokenStore.clear();
        _resetIdentity();
        _status = AuthStatus.unauthenticated;
      } else {
        // Server rejected the session for a non-expiry reason (e.g. 403):
        // treat as signed out locally rather than opening shells.
        await _repository.tokenStore.clear();
        _resetIdentity();
        _status = AuthStatus.unauthenticated;
      }
    } on Exception {
      // Offline/timeout: land on Public Home but keep tokens for retry.
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    _status = AuthStatus.authenticating;
    notifyListeners();
    try {
      final outcome = await _repository.login(
        identifier: identifier,
        password: password,
      );
      final access = outcome.access;
      final refresh = outcome.refresh;
      if (access == null || refresh == null) {
        throw const AuthException(
          'Missing session tokens.',
          code: 'BAD_RESPONSE',
        );
      }
      _applySession(outcome);
      _accessToken = access;
      _refreshToken = refresh;
      await _repository.tokenStore.writeAccess(access);
      await _repository.tokenStore.writeRefresh(refresh);
      _lastError = null;
      _status = AuthStatus.authenticated;
    } on AuthException catch (e) {
      _lastError = e;
      _status = AuthStatus.authError;
    }
    notifyListeners();
  }

  Future<void> logout() async {
    _status = AuthStatus.loggingOut;
    notifyListeners();
    try {
      final inMemoryRefresh = _refreshToken;
      final refresh = inMemoryRefresh ??
          await _repository.tokenStore.readRefresh();
      if (refresh != null) {
        await _repository.logout(refresh: refresh);
      }
    } on AuthException catch (e) {
      _lastError = e;
    } finally {
      await _repository.tokenStore.clear();
      _resetIdentity();
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  /// GET /auth/me — refreshes the safe identity subset (name, email, status,
  /// roles, verification) for existing sessions without rotating tokens.
  /// Failures are silent here: screens keep whatever identity they already hold.
  Future<void> refreshIdentity() async {
    final access = _accessToken;
    if (access == null) return;
    try {
      final outcome = await _repository.me(access: access);
      _applySession(outcome);
      if (outcome.accountStatus != null) {
        _status = outcome.accountStatus == 'ACTIVE' ||
                outcome.accountStatus == 'PENDING_VERIFICATION'
            ? AuthStatus.authenticated
            : _status;
      }
      notifyListeners();
    } on AuthException {
      // Keep existing identity; session lifecycle handled elsewhere.
    }
  }

  /// POST /auth/register — self-registerable roles only; the backend issues a
  /// one-time email-verification code and the account stays PENDING_VERIFICATION.
  Future<void> register({
    required String email,
    required String password,
    String? phone,
    String? firstName,
    String? lastName,
    String roleCode = 'PATIENT',
  }) async {
    _status = AuthStatus.authenticating;
    notifyListeners();
    try {
      await _repository.register(
        email: email,
        password: password,
        phone: phone,
        firstName: firstName,
        lastName: lastName,
        roleCode: roleCode,
      );
      // Not signed in yet — the signup flow proceeds to email verification.
      _email = email;
      _status = AuthStatus.tokenExpired; // awaits verification (§16)
    } on AuthException catch (e) {
      _lastError = e;
      _status = AuthStatus.authError;
    }
    notifyListeners();
  }

  /// POST /auth/verify/email — consume the one-time verification code.
  Future<void> verifyEmail({required String token}) async {
    _sessionBusy = true;
    notifyListeners();
    try {
      await _repository.verifyEmail(token: token);
      _emailVerified = true;
      _status = AuthStatus.unauthenticated;
      _lastError = null;
    } on AuthException catch (e) {
      _lastError = e;
      _status = AuthStatus.authError;
      rethrow;
    } finally {
      _sessionBusy = false;
      notifyListeners();
    }
  }

  /// POST /auth/verify/email/resend — uniform 202, no enumeration.
  Future<void> resendEmailVerification({required String email}) async {
    _sessionBusy = true;
    notifyListeners();
    try {
      await _repository.resendEmailVerification(email: email);
      _lastError = null;
    } on AuthException catch (e) {
      _lastError = e;
      rethrow;
    } finally {
      _sessionBusy = false;
      notifyListeners();
    }
  }

  Future<void> refreshSession() async {
    final refresh = _refreshToken;
    if (refresh == null) return;
    try {
      final outcome = await _repository.refresh(refresh: refresh);
      final access = outcome.access;
      final nextRefresh = outcome.refresh;
      if (access == null || nextRefresh == null) {
        throw const AuthException(
          'Missing session tokens.',
          code: 'BAD_RESPONSE',
        );
      }
      _accessToken = access;
      _refreshToken = nextRefresh;
      await _repository.tokenStore.writeAccess(access);
      await _repository.tokenStore.writeRefresh(nextRefresh);
      _status = AuthStatus.authenticated;
    } on AuthException catch (e) {
      _lastError = e;
      _status = AuthStatus.tokenExpired;
    }
    notifyListeners();
  }
}