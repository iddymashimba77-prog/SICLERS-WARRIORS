"""Community anti-abuse throttles (security-design §29, traceability §7).

Approved rates:
  * community post/comment/reaction    30/min
  * community report                   30/min
  * moderation resolve                 60/hour
"""

from rest_framework.throttling import SimpleRateThrottle


class _UserScopedThrottle(SimpleRateThrottle):
    def get_cache_key(self, request, view):
        user = getattr(request, "user", None)
        if user and user.is_authenticated:
            return self.cache_format % {"scope": self.scope, "ident": user.pk}
        return None


class CommunityPostThrottle(_UserScopedThrottle):
    rate = "30/min"
    scope = "community.post"


class CommunityInteractionThrottle(_UserScopedThrottle):
    rate = "30/min"
    scope = "community.interaction"


class CommunityReportThrottle(_UserScopedThrottle):
    rate = "30/min"
    scope = "community.report"


class CommunityResolveThrottle(_UserScopedThrottle):
    rate = "60/hour"
    scope = "community.resolve"
