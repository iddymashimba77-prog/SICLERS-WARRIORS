"""Chat anti-abuse throttles (security-design §29).

Approved rate: conversation create 60/min. Message send uses the same 60/min
spam ceiling (no separate approved rate, so we do not invent a different one).
"""

from rest_framework.throttling import SimpleRateThrottle


class _UserScopedThrottle(SimpleRateThrottle):
    def get_cache_key(self, request, view):
        user = getattr(request, "user", None)
        if user and user.is_authenticated:
            return self.cache_format % {"scope": self.scope, "ident": user.pk}
        return None


class ChatCreateThrottle(_UserScopedThrottle):
    rate = "60/min"
    scope = "chat.create"


class ChatMessageThrottle(_UserScopedThrottle):
    rate = "60/min"
    scope = "chat.message"
