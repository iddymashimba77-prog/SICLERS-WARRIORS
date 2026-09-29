"""Education anti-abuse throttles (security-api-traceability §7).

Current interpretation (matching how Stage 4.10 applied the community rates):

  * content writes (create/update/submit/delete)    30/min
  * admin review                                    60/hour
  * public reads fall through to the global anon/user rates

``_UserScopedThrottle`` returns no key for anonymous users, so public reads rely
on the global ``anon`` rate; the 30/min write cap applies to authenticated
publishers/reviewers.
"""

from rest_framework.throttling import SimpleRateThrottle


class _UserScopedThrottle(SimpleRateThrottle):
    def get_cache_key(self, request, view):
        user = getattr(request, "user", None)
        if user and user.is_authenticated:
            return self.cache_format % {"scope": self.scope, "ident": user.pk}
        return None


class EducationContentThrottle(_UserScopedThrottle):
    rate = "30/min"
    scope = "education.content"


class EducationReviewThrottle(_UserScopedThrottle):
    rate = "60/hour"
    scope = "education.review"