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

  /// The underlying repository — used by flows that need direct backend
  /// access under the session's own token (e.g. verification-document upload).
  AuthRepository get repository => _repository;

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

  String? _photoUrl;
  String? get photoUrl => _photoUrl;

  /// In-session photo swap after a successful upload. The avatar path is
  /// stable, so callers pass a cache-busting version query — every avatar
  /// surface drops the previously cached image; a cold start re-reads the
  /// clean server URL when the memory cache is empty anyway.
  void applyPhotoUrl(String url) {
    _photoUrl = url;
    notifyListeners();
  }

  /// Whether the account has configured its 4-digit login PIN (server-asserted).
  bool _hasLoginPin = false;
  bool get hasLoginPin => _hasLoginPin;

  /// The identifier (email/phone) of the account that configured a PIN on this
  /// device — what the PIN screen signs in as. Null when no account is
  /// remembered.
  String? _rememberedIdentity;
  String? get rememberedIdentity => _rememberedIdentity;

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
    _photoUrl = null;
    _hasLoginPin = false;
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
    _photoUrl = outcome.photoUrl;
    _hasLoginPin = outcome.hasLoginPin;
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
    // The remembered identity is independent of token validity: it lets the
    // PIN screen pre-fill the account even after a sign-out/expiry.
    _rememberedIdentity = await _repository.tokenStore.readRememberedIdentity();
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
      // A password login on an account that already has a PIN remembers this
      // device's identity so the next sign-in can use the PIN alone.
      final identity = _email;
      if (_hasLoginPin && identity != null && identity.trim().isNotEmpty) {
        _rememberedIdentity = identity;
        await _repository.tokenStore.writeRememberedIdentity(identity);
      }
      _lastError = null;
      _status = AuthStatus.authenticated;
    } on AuthException catch (e) {
      _lastError = e;
      _status = AuthStatus.authError;
    } on Exception {
      // Network/timeout/parse failures never reach the server. Surface a
      // single friendly message instead of letting the raw exception escape
      // (which left the submit button spinning with no explanation).
      _lastError = const AuthException(
        'Connection lost. Check your network and try again.',
        code: 'NETWORK_ERROR',
      );
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
    // A previous attempt's failure must not survive into this one — otherwise
    // a successful sign-up still renders the old error banner.
    _lastError = null;
    notifyListeners();
    try {
      final outcome = await _repository.register(
        email: email,
        password: password,
        phone: phone,
        firstName: firstName,
        lastName: lastName,
        roleCode: roleCode,
      );
      _email = email;
      // A freshly registered account has no PIN yet — the caller routes to the
      // "create PIN" step before entering the app.
      _hasLoginPin = false;
      if (outcome.signedIn) {
        // The server issues an identity-bound pair at registration. Persist it
        // the same way login does, so the app is genuinely signed in instead
        // of asking for a needless second login.
        final access = outcome.access!;
        final refresh = outcome.refresh!;
        _accessToken = access;
        _refreshToken = refresh;
        await _repository.tokenStore.writeAccess(access);
        await _repository.tokenStore.writeRefresh(refresh);
        _lastError = null;
        _status = AuthStatus.authenticated;
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } on AuthException catch (e) {
      _lastError = e;
      _status = AuthStatus.authError;
    } on Exception {
      _lastError = const AuthException(
        'Connection lost. Check your network and try again.',
        code: 'NETWORK_ERROR',
      );
      _status = AuthStatus.authError;
    }
    notifyListeners();
  }

  /// POST /auth/pin/set — configure (or change) the 4-digit login PIN for the
  /// signed-in account, then remember this device's identity for PIN sign-in.
  Future<void> setLoginPin({required String pin}) async {
    final access = _accessToken;
    if (access == null) {
      _lastError = const AuthException(
        'Sign in required to configure a PIN.',
        code: 'NO_SESSION',
      );
      notifyListeners();
      return;
    }
    _sessionBusy = true;
    notifyListeners();
    try {
      await _repository.setLoginPin(access: access, pin: pin);
      _hasLoginPin = true;
      _lastError = null;
      final identity = _email;
      if (identity != null && identity.trim().isNotEmpty) {
        _rememberedIdentity = identity;
        await _repository.tokenStore.writeRememberedIdentity(identity);
      }
    } on AuthException catch (e) {
      _lastError = e;
      rethrow;
    } finally {
      _sessionBusy = false;
      notifyListeners();
    }
  }

  /// Forget the remembered identity (e.g. "use another account") so the login
  /// screen falls back to the email+password form.
  Future<void> forgetRememberedIdentity() async {
    _rememberedIdentity = null;
    await _repository.tokenStore.clearRememberedIdentity();
    notifyListeners();
  }

  /// POST /auth/pin/login — PIN sign-in for the device-remembered identity.
  Future<void> loginWithPin({required String pin}) async {
    final identifier = _rememberedIdentity;
    if (identifier == null || identifier.trim().isEmpty) {
      _lastError = const AuthException(
        'No account is remembered on this device.',
        code: 'NO_REMEMBERED_IDENTITY',
      );
      _status = AuthStatus.authError;
      notifyListeners();
      return;
    }
    _status = AuthStatus.authenticating;
    _lastError = null;
    notifyListeners();
    try {
      final outcome = await _repository.loginWithPin(identifier: identifier, pin: pin);
      final access = outcome.access;
      final refresh = outcome.refresh;
      if (access == null || refresh == null) {
        throw const AuthException('Missing session tokens.', code: 'BAD_RESPONSE');
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
    } on Exception {
      _lastError = const AuthException(
        'Connection lost. Check your network and try again.',
        code: 'NETWORK_ERROR',
      );
      _status = AuthStatus.authError;
    }
    notifyListeners();
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
    } on Exception {
      _lastError = const AuthException(
        'Connection lost. Check your network and try again.',
        code: 'NETWORK_ERROR',
      );
      _status = AuthStatus.tokenExpired;
    }
    notifyListeners();
  }
}