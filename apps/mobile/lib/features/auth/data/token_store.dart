import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/auth_types.dart';

/// Secure-persistence contract for the JWT pair.
///
/// Production implementations should use platform secure storage
/// (Keychain/Keystore). Passwords are never stored here.
abstract class TokenStore {
  Future<void> writeAccess(String token);

  Future<void> writeRefresh(String token);

  Future<String?> readAccess();

  Future<String?> readRefresh();

  Future<void> clear();
}

/// In-memory token store.
///
/// Used for local development and widget tests.
/// It is not intended for production authenticated sessions.
class EphemeralTokenStore implements TokenStore {
  String? _access;
  String? _refresh;

  @override
  Future<void> writeAccess(String token) async {
    _access = token;
  }

  @override
  Future<void> writeRefresh(String token) async {
    _refresh = token;
  }

  @override
  Future<String?> readAccess() async {
    return _access;
  }

  @override
  Future<String?> readRefresh() async {
    return _refresh;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}

/// Persistent JWT store backed by [SharedPreferences].
///
/// Sessions survive app restarts and are *not* part of the theme/language
/// preferences (sign-out clears only these keys). Production hardening — e.g.
/// platform secure storage via Keychain/Keystore or an encrypted database — is
/// called out in the report; this persistence keeps the real login flow working
/// across launches without exposing tokens in any source-controlled file.
class SharedPrefsTokenStore implements TokenStore {
  SharedPrefsTokenStore();

  static const String _accessKey = 'sw.auth.access';
  static const String _refreshKey = 'sw.auth.refresh';

  Future<SharedPreferences?> get _prefs async {
    try {
      return await SharedPreferences.getInstance()
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {
      // Plugin channel unavailable (widget tests / exotic platforms): degrade
      // to non-persistent reads/writes so flows never crash.
      return null;
    }
  }

  @override
  Future<void> writeAccess(String token) async {
    await (await _prefs)?.setString(_accessKey, token);
  }

  @override
  Future<void> writeRefresh(String token) async {
    await (await _prefs)?.setString(_refreshKey, token);
  }

  @override
  Future<String?> readAccess() async => (await _prefs)?.getString(_accessKey);

  @override
  Future<String?> readRefresh() async => (await _prefs)?.getString(_refreshKey);

  @override
  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs?.remove(_accessKey);
    await prefs?.remove(_refreshKey);
  }
}

/// Standard authentication response envelope.
class AuthEnvelope {
  const AuthEnvelope({
    required this.access,
    required this.refresh,
    required this.user,
  });

  final String access;
  final String refresh;
  final Map<String, dynamic> user;
}

/// Parses the standard backend response envelope.
AuthEnvelope parseEnvelope(
  String body, {
  int statusCode = 200,
}) {
  try {
    final decoded = jsonDecode(body);

    if (decoded is! Map<String, dynamic>) {
      throw const AuthException(
        'Unexpected server response.',
        code: 'BAD_RESPONSE',
        statusCode: 500,
      );
    }

    final error = decoded['error'];

    if (error is Map<String, dynamic>) {
      final message =
          (error['message'] as String?) ??
          (error['detail'] as String?) ??
          'Request failed.';

      final code = error['code'] as String?;

      final details = error['details'];

      final fieldErrors = <String, List<String>>{};

      if (details is Map<String, dynamic>) {
        details.forEach((key, value) {
          fieldErrors[key] = [
            if (value is List)
              ...value.map((item) => item.toString())
            else
              value.toString(),
          ];
        });
      }

      throw AuthException(
        message,
        code: code,
        statusCode: statusCode,
        fieldErrors: fieldErrors,
      );
    }

    final data = decoded['data'];

    if (data is! Map<String, dynamic>) {
      throw const AuthException(
        'Unexpected server response.',
        code: 'BAD_RESPONSE',
        statusCode: 500,
      );
    }

    final user = data['user'] is Map<String, dynamic>
        ? data['user'] as Map<String, dynamic>
        : <String, dynamic>{};

    final access = data['access'] as String?;
    final refresh = data['refresh'] as String?;

    if (access == null || refresh == null) {
      throw const AuthException(
        'Missing session tokens.',
        code: 'BAD_RESPONSE',
        statusCode: 500,
      );
    }

    return AuthEnvelope(
      access: access,
      refresh: refresh,
      user: user,
    );
  } on AuthException {
    rethrow;
  } on FormatException {
    throw const AuthException(
      'Unexpected server response.',
      code: 'BAD_RESPONSE',
      statusCode: 500,
    );
  } catch (_) {
    throw const AuthException(
      'Unexpected server response.',
      code: 'BAD_RESPONSE',
      statusCode: 500,
    );
  }
}
