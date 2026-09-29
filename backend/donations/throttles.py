"""Donations / payments anti-abuse throttles (security-api-design §29).

Approved starting points (tunable per env, calibrated under load):

  * donation/payment initiation       10/hour/user
  * per-campaign burst                 2/10min per campaign per user
  * campaign writes (create/patch/submit)  30/min/user
  * webhooks                          provider IP allowlist + signature
                                      (enforced in PaymentWebhookAccess, not a
                                       rate — sees max ~1 event per change)

``_UserScopedThrottle`` returns no key for anonymous users so public reads fall
through to the global anon/user rates.
"""

from rest_framework.throttling import SimpleRateThrottle


class _UserScopedThrottle(SimpleRateThrottle):
    def get_cache_key(self, request, view):
        user = getattr(request, "user", None)
        if user and user.is_authenticated:
            return self.cache_format % {"scope": self.scope, "ident": user.pk}
        return None


class DonationInitiateThrottle(_UserScopedThrottle):
    """Donation/payment initiation — 10/hour/user (api-design §29)."""

    rate = "10/hour"
    scope = "donation.create"


class CampaignDonationBurstThrottle(SimpleRateThrottle):
    """Per-campaign burst — 2/min per campaign per user (§29)."""

    rate = "2/min"
    scope = "donation.burst"

    def get_cache_key(self, request, view):
        user = getattr(request, "user", None)
        if not (user and user.is_authenticated):
            return None
        campaign_uid = None
        try:
            data = request.data or {}
        except Exception:  # pragma: no cover — defensive, parsing must not crash
            data = {}
        if isinstance(data, dict):
            campaign_uid = data.get("campaign_uid")
        campaign_uid = getattr(campaign_uid, "hex", None) or campaign_uid
        if not campaign_uid:
            return None
        return self.cache_format % {
            "scope": self.scope, "ident": f"{campaign_uid}:{user.pk}",
        }


class CampaignWriteThrottle(_UserScopedThrottle):
    """Campaign writes (create/patch/submit) — 30/min/user."""

    rate = "30/min"
    scope = "campaign.write"