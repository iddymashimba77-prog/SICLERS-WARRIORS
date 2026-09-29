"""Auth brute-force throttles (Stage 4.17 §26).

A dedicated ``auth`` scope protects the credential/account endpoints
(login, register, logout, refresh, password-reset) so a scripted attacker
cannot grind passwords or enumerate accounts at system speed.

Keying: per presented identity when one is supplied (email/phone/token), else
per remote address. The identifier is hashed so cache keys never hold PII and
an attacker spamming many fake identifiers still shares the IP-level budget.
"""

import hashlib

from rest_framework.throttling import SimpleRateThrottle


class AuthThrottle(SimpleRateThrottle):
    """Per-identity (or per-IP) budget for authentication endpoints."""

    scope = "auth"

    def _identity(self, request) -> str:
        if request.method not in ("POST", "PATCH", "PUT"):
            return self.get_ident(request)
        data = getattr(request, "data", None)
        if isinstance(data, dict):
            for key in ("email_or_phone", "email", "phone", "username", "refresh", "token"):
                value = data.get(key)
                if isinstance(value, str) and value.strip():
                    return value.strip().lower()
        return self.get_ident(request)

    def get_cache_key(self, request, view):
        identifier = self._identity(request)
        ident = hashlib.sha256(identifier.encode("utf-8")).hexdigest()[:20]
        return self.cache_format % {"scope": self.scope, "ident": ident}