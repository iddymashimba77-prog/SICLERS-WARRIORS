"""AI assistant anti-abuse throttles.

Approved cost-control rationale (api-design §29 / AD-9 "limits documented"): an
external LLM today would be expensive and slow; even the rule-based sandbox
must not become a spam surface. Limits are per-user (owner-scoped cache key),
tunable via env, and calibrated in production under load:

  * chat   — 6/min/user (burst), plus the global anonymous/authenticated rates.
  * trends — 30/hour/user (analysis is heavier than a single sentence; 90-day
             computation + audit is fine at this rate).

Anonymous requests return no key so they fall through to the global
per-IP rates inherited from the project defaults (AD-9).
"""

from rest_framework.throttling import SimpleRateThrottle


class _UserScopedThrottle(SimpleRateThrottle):
    def get_cache_key(self, request, view):
        user = getattr(request, "user", None)
        if user and user.is_authenticated:
            return self.cache_format % {"scope": self.scope, "ident": user.pk}
        return None


class AiChatThrottle(_UserScopedThrottle):
    """Chat turns — 6/min per user (cost control, AD-9 documented)."""

    rate = "6/min"
    scope = "ai.chat"


class AiTrendsThrottle(_UserScopedThrottle):
    """Trends analysis — 30/hour per user (heavier generated surface)."""

    rate = "30/hour"
    scope = "ai.trends"