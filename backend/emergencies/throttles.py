"""Emergency create throttle (BR-009: anti-spam).

Route personal emergency creation at 3 requests/hour/user. Rejects with 429
(RATE_LIMITED) beyond that; the throttle outcome is recorded on
``EmergencyRequest.rate_limit_ok`` by the view (design keeps it as a bool).
"""

from rest_framework.throttling import SimpleRateThrottle


class EmergencyCreateThrottle(SimpleRateThrottle):
    rate = "3/hour"
    scope = "emergency.create"

    def get_cache_key(self, request, view):
        user = getattr(request, "user", None)
        if user and user.is_authenticated:
            return self.cache_format % {"scope": self.scope, "ident": user.pk}
        return None