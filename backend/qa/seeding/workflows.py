"""Phase 10 — real admin workflows through the in-process HTTP API.

Nothing here bypasses the service layer: every decision is made by POSTing to the
same DRF endpoints a real verification officer / admin uses, authenticated with a
JWT minted for the seeded admin. Dev ``ALLOWED_HOSTS=["*"]`` accepts the
``testserver`` host that DRF's ``APIClient`` uses, and the cache is cleared so the
project's throttles never trip over the seed's burst of calls.

The tags left by the earlier phases are what make this idempotent: only records
still in their ``PENDING*`` / ``IN_REVIEW`` states are acted on, so a re-run makes
no further transitions.
"""

from __future__ import annotations

from django.core.cache import cache
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from blood_network.models import BloodRequest
from doctors.models import Doctor
from donations.models import Campaign
from education.models import EducationalContent
from facilities.models import Facility

from .base import TAG


def _client(ctx) -> APIClient:
    cache.clear()
    client = APIClient()
    token = RefreshToken.for_user(ctx.admin).access_token
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
    return client


def _post(ctx, client, url, data, label, counter):
    resp = client.post(url, data, format="json")
    ctx.counts["workflow_calls"] = ctx.counts.get("workflow_calls", 0) + 1
    if resp.status_code in (200, 201):
        ctx.track(counter)
        return True
    ctx.log(f"- WARN {label} -> {resp.status_code} {getattr(resp, 'data', '')}")
    return False


def run(ctx) -> None:
    if ctx.admin is None:
        from accounts.models import User
        ctx.admin = (
            User.objects.filter(user_roles__role__code="SUPER_ADMIN").order_by("pk").first()
        )
    client = _client(ctx)
    ctx.log("## Admin verification workflows (via real HTTP API)")

    professionals = list(
        Doctor.objects.filter(verification_status="PENDING")
        .select_related("user").order_by("pk")[:60]
    )
    for i, prof in enumerate(professionals, start=1):
        approve = i % 6 != 0
        payload = {"approve": approve}
        if not approve:
            payload["reason"] = f"{TAG} incomplete registration documents."
        _post(
            ctx, client, f"/api/admin/doctors/{prof.user.uid}/verify/", payload,
            f"doctor#{prof.pk}",
            "doctors_approved" if approve else "doctors_rejected",
        )
    approved = Doctor.objects.filter(verification_status="APPROVED").select_related("user").first()
    if approved:
        _post(client=client, ctx=ctx, url=f"/api/admin/doctors/{approved.user.uid}/suspend/",
              data={"reason": f"{TAG} temporary suspension for QA."}, label="doctor suspend",
              counter="doctors_suspended")
        _post(ctx, client, f"/api/admin/doctors/{approved.user.uid}/reinstate/",
              {"reason": f"{TAG} reinstated after review."}, "doctor reinstate",
              "doctors_reinstated")

    facilities = list(Facility.objects.filter(is_verified=False).order_by("pk")[:60])
    for i, fac in enumerate(facilities, start=1):
        approve = i % 5 != 0
        payload = {"approve": approve}
        if not approve:
            payload["reason"] = f"{TAG} missing licence details."
        _post(
            ctx, client, f"/api/admin/facilities/{fac.uid}/verify", payload, f"facility#{fac.pk}",
            "facilities_approved" if approve else "facilities_rejected",
        )

    pending = list(BloodRequest.objects.filter(status="PENDING_VERIFICATION").order_by("pk"))
    for i, req in enumerate(pending, start=1):
        if i % 4 == 0:
            _post(ctx, client, f"/api/admin/blood/requests/{req.uid}/reject/",
                  {"reason": f"{TAG} duplicate request."}, f"blood-reject#{req.pk}",
                  "blood_requests_rejected")
        else:
            _post(ctx, client, f"/api/admin/blood/requests/{req.uid}/verify/",
                  {"reason": f"{TAG} verified during QA."}, f"blood-verify#{req.pk}",
                  "blood_requests_approved")

    campaigns = list(Campaign.objects.filter(status="PENDING_VERIFICATION").order_by("pk"))
    for i, campaign in enumerate(campaigns, start=1):
        approve = i % 4 != 0
        payload = {"approve": approve}
        if not approve:
            payload["reason"] = f"{TAG} incomplete campaign documentation."
        _post(ctx, client, f"/api/admin/campaigns/{campaign.uid}/verify/", payload,
              f"campaign#{campaign.pk}",
              "campaigns_approved" if approve else "campaigns_rejected")

    in_review = list(EducationalContent.objects.filter(status="IN_REVIEW").order_by("pk"))
    for i, content in enumerate(in_review, start=1):
        approve = i % 3 != 0
        payload = {"decision": "approve" if approve else "reject"}
        if not approve:
            payload["reason"] = f"{TAG} needs a medical citation."
        _post(ctx, client, f"/api/admin/education/content/{content.uid}/review/", payload,
              f"education#{content.pk}",
              "education_approved" if approve else "education_rejected")

    ctx.log(
        f"- API calls: {ctx.counts.get('workflow_calls', 0)} | "
        f"doctors +{ctx.counts.get('doctors_approved', 0)}/-{ctx.counts.get('doctors_rejected', 0)} "
        f"(susp/rei {ctx.counts.get('doctors_suspended', 0)}/{ctx.counts.get('doctors_reinstated', 0)}), "
        f"facilities +{ctx.counts.get('facilities_approved', 0)}/-{ctx.counts.get('facilities_rejected', 0)}, "
        f"blood +{ctx.counts.get('blood_requests_approved', 0)}/-{ctx.counts.get('blood_requests_rejected', 0)}, "
        f"campaigns +{ctx.counts.get('campaigns_approved', 0)}/-{ctx.counts.get('campaigns_rejected', 0)}, "
        f"education +{ctx.counts.get('education_approved', 0)}/-{ctx.counts.get('education_rejected', 0)}"
    )
