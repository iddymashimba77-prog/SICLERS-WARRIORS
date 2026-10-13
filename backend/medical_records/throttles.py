"""Clinical-record anti-abuse throttles (security-api-traceability §7).

Clinical data is the most sensitive surface in the system, so its write rates
are tighter than the community/content ones:

  * record create/update/status/visibility   30/min
  * file upload                              20/min
  * share / revoke-share                     20/min
  * reads fall through to the global anon/user rates

`_UserScopedThrottle` returns no key for anonymous callers, so an unauthenticated
request is rejected by the permission class before any throttle applies.
"""

from rest_framework.throttling import SimpleRateThrottle


class _UserScopedThrottle(SimpleRateThrottle):
    def get_cache_key(self, request, view):
        user = getattr(request, "user", None)
        if user and user.is_authenticated:
            return self.cache_format % {"scope": self.scope, "ident": user.pk}
        return None


class MedicalRecordWriteThrottle(_UserScopedThrottle):
    rate = "30/min"
    scope = "medical_records.write"


class MedicalRecordFileThrottle(_UserScopedThrottle):
    rate = "20/min"
    scope = "medical_records.file"


class MedicalRecordShareThrottle(_UserScopedThrottle):
    rate = "20/min"
    scope = "medical_records.share"