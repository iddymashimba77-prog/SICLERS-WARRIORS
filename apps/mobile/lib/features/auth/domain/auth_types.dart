/// Authentication domain types for Sickler's Warriors.
///
/// These types are shared across the authentication data and presentation
/// layers. No passwords, JWTs, or backend-internal details belong here.

library;

enum AuthStatus {
  /// App start: session store is being probed and (if a token exists) validated
  /// against /auth/me before any route decision is made (AUTH-2).
  initializing,
  unauthenticated,
  authenticating,
  authenticated,
  tokenExpired,
  loggingOut,
  authError,
}

class AuthException implements Exception {
  const AuthException(
    this.message, {
    this.code,
    this.statusCode,
    this.fieldErrors = const {},
  });

  final String message;
  final String? code;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;

  bool get isValidation =>
      statusCode == 422 && fieldErrors.isNotEmpty;

  @override
  String toString() => 'AuthException($code): $message';

  @override
  int get hashCode => Object.hash(
        message,
        code,
        statusCode,
        fieldErrors,
      );

  @override
  bool operator ==(Object other) =>
      other is AuthException &&
      other.message == message &&
      other.code == code &&
      other.statusCode == statusCode &&
      _mapsEqual(other.fieldErrors, fieldErrors);
}

bool _mapsEqual(
  Map<String, List<String>> a,
  Map<String, List<String>> b,
) {
  if (a.length != b.length) return false;

  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null) return false;
    if (other.length != entry.value.length) return false;

    for (var i = 0; i < entry.value.length; i++) {
      if (entry.value[i] != other[i]) return false;
    }
  }

  return true;
}

bool isPasswordLongEnough(String value) => value.length >= 8;

bool isPasswordStrongEnough(String value) =>
    value.length >= 8 &&
    value.runes.where((r) => r < 0x80).length == value.runes.length &&
    value.contains(RegExp(r'[A-Za-z]')) &&
    value.contains(RegExp(r'\d'));
