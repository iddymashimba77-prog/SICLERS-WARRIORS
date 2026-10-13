import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_config.dart';
import '../domain/auth_types.dart';
import 'token_store.dart';

/// One fetch/refresh/lifecycle unit: each authentication endpoint returns an
/// access token + optional refresh + safe identity subset (§ me contract).
class AuthSessionOutcome {
  const AuthSessionOutcome({
    this.access,
    this.refresh,
    this.email,
    this.accountStatus,
    this.firstName,
    this.lastName,
    this.roles = const [],
    this.permissions = const [],
    this.isVerifiedDoctor = false,
    this.doctorVerificationStatus,
    this.facility,
    this.hasLoginPin = false,
    this.photoUrl,
  });

  final String? access;
  final String? refresh;
  final String? email;
  final String? accountStatus;
  final String? firstName;
  final String? lastName;
  final List<String> roles;
  final List<String> permissions;

  /// Server-authenticated verification state (AUTH-2). Account type is never
  /// verification: only /auth/me + login may assert reality.
  final bool isVerifiedDoctor;
  final String? doctorVerificationStatus;
  final Map<String, dynamic>? facility;

  /// Whether the account has configured its 4-digit login PIN. Drives the
  /// post-auth "create PIN" step vs entering the app directly.
  final bool hasLoginPin;

  /// Absolute profile-photo URL read from the server identity contract
  /// (`profile_photo_url`, § me).
  final String? photoUrl;
}

/// Backend client for the authenticated endpoints. Centralized here — auth
/// logic never lives in screens (§26). Endpoints mirror
/// `backend/accounts/urls.py` + the OpenAPI schema:
///
///   POST /api/auth/register/
///   POST /api/auth/login/
///   POST /api/auth/logout/
///   POST /api/auth/refresh/
///   GET  /api/auth/me/
/// What the server returned for a registration attempt.
///
/// The server issues an identity-bound JWT pair at registration, so the client
/// must not discard the response: either the account is immediately usable
/// ([signedIn] true) or it is gated on email verification.
class RegisterOutcome {
  const RegisterOutcome({
    this.access,
    this.refresh,
    this.verificationRequired = false,
  });

  final String? access;
  final String? refresh;

  /// Server hint that a professional/facility applicant must upload
  /// government-verified documents (C5 pipeline) before their account may
  /// transact. Patients, caregivers and blood donors register freely.
  final bool verificationRequired;

  bool get signedIn => (access?.isNotEmpty ?? false) && (refresh?.isNotEmpty ?? false);
}

/// One uploaded verification document: a storage key returned by the backend
/// upload endpoint, ready to attach to a doctors/facilities submission.
class VerificationUploadedDoc {
  const VerificationUploadedDoc({
    required this.docType,
    required this.fileUrl,
    this.fileName = '',
    this.localPath,
  });

  final String docType;
  final String fileUrl;
  final String fileName;
  final String? localPath;
}

class AuthRepository {
  AuthRepository({required this.tokenStore, http.Client? client})
      : _client = client ?? http.Client();

  final TokenStore tokenStore;
  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  Uri _uri(String segment) =>
      Uri.parse('${AppConfig.apiBaseUrl}/auth/$segment/');

  Uri _apiUri(String segment) =>
      Uri.parse('${AppConfig.apiBaseUrl}/$segment/');

  Map<String, String> get _jsonHeaders => const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// Maps a backend ``user`` summary onto the session outcome. Verification
  /// fields are read straight from the server contract; never synthesized.
  AuthSessionOutcome _outcomeFrom(
    Map<String, dynamic> payload, {
    String? access,
    String? refresh,
  }) {
    final user = payload['user'] as Map<String, dynamic>? ?? const {};
    return AuthSessionOutcome(
      access: access ?? payload['access'] as String?,
      refresh: refresh ?? payload['refresh'] as String?,
      email: user['email'] as String?,
      accountStatus: user['account_status'] as String?,
      firstName: user['first_name'] as String?,
      lastName: user['last_name'] as String?,
      roles: [...?(user['role_codes'] as List?)?.cast<String>()],
      permissions: [...?(user['permission_codes'] as List?)?.cast<String>()],
      isVerifiedDoctor: user['is_verified_doctor'] == true,
      doctorVerificationStatus: user['doctor_verification_status'] as String?,
      facility:
          user['facility'] is Map<String, dynamic> ? user['facility'] as Map<String, dynamic> : null,
      hasLoginPin: user['has_login_pin'] == true,
      photoUrl: user['profile_photo_url'] as String?,
    );
  }

  AuthException _errorFrom(http.Response res, String body) {
    // Safe parse: never surface server internals.
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final err = map['error'] as Map<String, dynamic>? ?? const {};
      final details = (err['details'] as Map<String, dynamic>?) ?? const {};
      final fieldErrors = <String, List<String>>{};
      details.forEach((field, msgs) {
        fieldErrors[field] = [
          for (final m in msgs is List ? msgs : [msgs]) '$m',
        ];
      });
      return AuthException(
        (err['message'] as String?) ?? 'Request failed.',
        code: (err['code'] as String?) ?? 'API_ERROR',
        statusCode: res.statusCode,
        fieldErrors: fieldErrors,
      );
    } catch (_) {
      return AuthException(
        res.statusCode >= 500
            ? 'Server error. Please try again shortly.'
            : 'Request failed (${res.statusCode}).',
        code: 'API_ERROR',
        statusCode: res.statusCode,
      );
    }
  }

  /// POST /auth/register — only self-registerable roles are ever sent
  /// (never ADMIN/etc — §18/§C17).
  Future<RegisterOutcome> register({
    required String email,
    required String password,
    String? phone,
    String? firstName,
    String? lastName,
    String roleCode = 'PATIENT',
  }) async {
    final body = jsonEncode({
      'email': email.trim(),
      'password': password,
      if (phone != null) 'phone': phone,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      'role_code': roleCode, // server re-validates; self-claims never trusted
    });
    final res = await _client
        .post(_uri('register'), headers: _jsonHeaders, body: body)
        .timeout(_timeout);
    if (res.statusCode >= 400) {
      throw _errorFrom(res, res.body);
    }
    // Read the tokens the server issued. Discarding this body is what left the
    // app in a "registered but not signed in, and showing the previous error"
    // state after a successful sign-up.
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final payload = data['data'] as Map<String, dynamic>? ?? data;
    return RegisterOutcome(
      access: payload['access'] as String?,
      refresh: payload['refresh'] as String?,
      verificationRequired: payload['verification_required'] as bool? ?? false,
    );
  }

  /// POST /auth/verification/documents/upload — store one government-issued
  /// document scan (multipart). Images are re-encoded server-side; PDFs are
  /// stored raw. Provide raw [fileBytes] when the platform has no filesystem
  /// path (Flutter web) or a [filePath] on mobile/desktop. Returns the storage
  /// key to attach to a submission.
  Future<VerificationUploadedDoc> uploadVerificationDocument({
    required String access,
    required String docType,
    String? filePath,
    String? fileName,
    Uint8List? fileBytes,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('verification/documents/upload'),
    )
      ..headers['Accept'] = 'application/json'
      ..headers['Authorization'] = 'Bearer $access'
      ..fields['doc_type'] = docType;
    if (fileBytes != null) {
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName ?? 'document.bin',
      ));
    } else {
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        filePath!,
        filename: fileName ?? filePath.split('/').last,
      ));
    }
    final streamed = await _client.send(request).timeout(const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final payload = data['data'] as Map<String, dynamic>? ?? data;
    return VerificationUploadedDoc(
      docType: (payload['doc_type'] as String?) ?? docType,
      fileUrl: (payload['file_url'] as String?) ?? '',
      fileName: (payload['file_name'] as String?) ?? fileName ?? filePath ?? '',
      localPath: filePath,
    );
  }

  /// POST /doctors/me/verification or /facilities/me/verification — submit the
  /// uploaded document bundle with the professional/facility identity so the
  /// C5 review queue can decide. The server enforces the mandatory types.
  Future<void> submitVerificationDocuments({
    required String access,
    required bool isFacility,
    String professionalType = 'DOCTOR',
    Map<String, String> facilityProfile = const {},
    required List<VerificationUploadedDoc> documents,
  }) async {
    final docs = [
      for (final d in documents) {'doc_type': d.docType, 'file_url': d.fileUrl},
    ];
    final body = isFacility
        ? {...facilityProfile, 'documents': docs}
        : {'professional_type': professionalType, 'documents': docs};
    final res = await _client
        .post(
          isFacility
              ? _apiUri('facilities/me/verification')
              : _apiUri('doctors/me/verification'),
          headers: {..._jsonHeaders, 'Authorization': 'Bearer $access'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
  }

  /// POST /auth/login — issues access (+ refresh) pair on success.
  Future<AuthSessionOutcome> login({
    required String identifier,
    required String password,
  }) async {
    final body = jsonEncode({
      'email_or_phone': identifier.trim(),
      'password': password,
    });
    final res = await _client
        .post(_uri('login'), headers: _jsonHeaders, body: body)
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final payload = data['data'] as Map<String, dynamic>? ?? data;
    return _outcomeFrom(payload, access: payload['access'] as String?, refresh: payload['refresh'] as String?);
  }

  /// POST /auth/refresh — rotates the refresh token (§08). The old refresh is
  /// denylisted server-side; the presented one is never reused.
  Future<AuthSessionOutcome> refresh({required String refresh}) async {
    final body = jsonEncode({'refresh': refresh});
    final res = await _client
        .post(_uri('refresh'), headers: _jsonHeaders, body: body)
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final payload = data['data'] as Map<String, dynamic>? ?? data;
    return AuthSessionOutcome(
      access: payload['access'] as String?,
      refresh: payload['refresh'] as String?,
    );
  }

  /// POST /auth/logout — denylists the refresh family server-side (§12).
  /// Local tokens are cleared by the controller irrespective of the response.
  Future<void> logout({required String refresh}) async {
    try {
      final body = jsonEncode({'refresh': refresh});
      final res = await _client
          .post(_uri('logout'), headers: _jsonHeaders, body: body)
          .timeout(_timeout);
      if (res.statusCode >= 500) throw _errorFrom(res, res.body);
    } on AuthException {
      rethrow;
    } catch (_) {
      // Network failure: still clear locally — session must end locally (§12).
    }
  }

  /// POST /auth/password/change — requires the current password. The backend
  /// revokes every session including the current one, so on success the client
  /// must clear local tokens and sign the user back in (FRONTEND-3).
  Future<void> changePassword({
    required String access,
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = await _client.post(
      _uri('password/change'),
      headers: {..._jsonHeaders, 'Authorization': 'Bearer $access'},
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    ).timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
  }

  /// GET /auth/me — safe identity subset (§ me contract: role_codes,
  /// permission_codes, account_status). Never a password, token, or medical
  /// payload (§24).
  Future<AuthSessionOutcome> me({required String access}) async {
    final res = await _client.get(
      _uri('me'),
      headers: {..._jsonHeaders, 'Authorization': 'Bearer $access'},
    ).timeout(_timeout);
    if (res.statusCode == 401) {
      throw const AuthException('Session expired. Please sign in again.',
          code: 'TOKEN_EXPIRED', statusCode: 401);
    }
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final user = data['data'] as Map<String, dynamic>? ?? data;
    return _outcomeFrom({'user': user});
  }

  /// POST /auth/password-reset/request — requests a password reset code.
  /// Always returns 202 regardless of account existence to prevent enumeration.
  Future<void> requestPasswordReset({required String identifier}) async {
    final body = jsonEncode({'email_or_phone': identifier.trim()});
    final res = await _client
        .post(_uri('password-reset/request'), headers: _jsonHeaders, body: body)
        .timeout(_timeout);
    if (res.statusCode >= 500) throw _errorFrom(res, res.body);
    // 202 is success; 4xx errors are still surfaced
    if (res.statusCode >= 400 && res.statusCode < 500) {
      throw _errorFrom(res, res.body);
    }
  }

  /// POST /auth/password-reset/confirm — confirms a password reset with a token.
  Future<void> confirmPasswordReset({
    required String token,
    required String password,
  }) async {
    final body = jsonEncode({
      'token': token,
      'new_password': password,
    });
    final res = await _client
        .post(_uri('password-reset/confirm'), headers: _jsonHeaders, body: body)
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
  }

  /// POST /auth/pin/set — configure the 4-digit login PIN for the signed-in
  /// account. The PIN is hashed server-side; 204 on success.
  Future<void> setLoginPin({required String access, required String pin}) async {
    final res = await _client.post(
      _uri('pin/set'),
      headers: {..._jsonHeaders, 'Authorization': 'Bearer $access'},
      body: jsonEncode({'pin': pin}),
    ).timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
  }

  /// POST /auth/pin/login — sign in with the 4-digit PIN against the identity
  /// the device remembers. Issues a fresh access (+ refresh) pair.
  Future<AuthSessionOutcome> loginWithPin({
    required String identifier,
    required String pin,
  }) async {
    final body = jsonEncode({
      'email_or_phone': identifier.trim(),
      'pin': pin,
    });
    final res = await _client
        .post(_uri('pin/login'), headers: _jsonHeaders, body: body)
        .timeout(_timeout);
    if (res.statusCode >= 400) throw _errorFrom(res, res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final payload = data['data'] as Map<String, dynamic>? ?? data;
    return _outcomeFrom(
      payload,
      access: payload['access'] as String?,
      refresh: payload['refresh'] as String?,
    );
  }
}