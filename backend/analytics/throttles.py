"""Analytics anti-abuse throttles (security-api-traceability, admin rows).

Approved surface rates (security-api-traceability §admin):
  GET /admin/analytics    60/min/user   (aggregate reporting)
  GET /admin/dashboard    60/min/user   (same guard; cheap snapshot reads)

Exports are additionally gated by the C4 reason + audit layer in the export
path (10/h applies to the separate ``POST /admin/exports`` gap endpoint, which
is NOT implemented in this stage).
"""

from rest_framework.throttling import SimpleRateThrottle


class AnalyticsReadThrottle(SimpleRateThrottle):
    """60/min authenticated user — reporting + dashboard (snapshot reads)."""

    rate = "60/min"
    scope = "analytics.read"

    def get_cache_key(self, request, view):
        user = getattr(request, "user", None)
        if user and user.is_authenticated:
            return self.cache_format % {"scope": self.scope, "ident": user.pk}
        return None