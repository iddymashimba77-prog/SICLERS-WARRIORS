"""Content CMS anti-abuse throttles.

  * admin writes (create/update/status actions)   30/min
  * cover image uploads                           10/min
  * public reads rely on the global anon/user rates

``_UserScopedThrottle`` returns no key for anonymous users, so public reads fall
through to the project-wide rates (same interpretation as education §4.11).
"""

from rest_framework.throttling import SimpleRateThrottle


class _UserScopedThrottle(SimpleRateThrottle):
    def get_cache_key(self, request, view):
        user = getattr(request, "user", None)
        if user and user.is_authenticated:
            return self.cache_format % {"scope": self.scope, "ident": user.pk}
        return None


class ContentWriteThrottle(_UserScopedThrottle):
    rate = "30/min"
    scope = "content.manage"


class ContentCoverThrottle(_UserScopedThrottle):
    rate = "10/min"
    scope = "content.cover"