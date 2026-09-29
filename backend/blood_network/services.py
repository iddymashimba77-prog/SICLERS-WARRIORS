"""Blood matching engine (approved Stage 4.8).

Source of truth — database-design.md §8.5 & ERD line 290-291:
  * Matching = compatibility + location + availability.
  * Donor contact info is NEVER in a request/match payload (BR-006) — the
    donor's address/phone is only released at a facility, after an accepted
    match, inside an authorized clinical workflow.

Compatibility (RESULT SOTO): standard ABO/Rh donor→recipient mapping
(`RECIPIENT_ACCEPTABLE_DONORS` in models) — "can this donor donate to this
recipient group?". Always resolved from the recipient side.

Score (deterministic, documented, 0..1):
  exact group       0.300
  compatible group  0.200   (exact implies compatible)
  donation history  min(donation_count, 5) * 0.020   (proven donor)
  same region       0.050
  same city         0.100   (overrides region)
  available         0.150
The score is informational to the requester (ordering heuristic); it is never
used to disclose PHI and is derived from the same non-contact donor fields the
public subset already exposes.
"""

import logging

from django.db import transaction
from django.utils import timezone

from notifications.services import create_notification
from .models import (
    BloodDonor,
    BloodMatch,
    BloodRequest,
    RECIPIENT_ACCEPTABLE_DONORS,
)

logger = logging.getLogger(__name__)

MATCHABLE_STATUSES = ("PENDING_VERIFICATION", "ACTIVE")


def is_donor_compatible(donor_group: str, recipient_group: str) -> bool:
    """True when a donor of `donor_group` may donate to `recipient_group`."""
    return donor_group in RECIPIENT_ACCEPTABLE_DONORS.get(recipient_group, set())


def is_donor_eligible(request: BloodRequest, donor: BloodDonor) -> bool:
    """C8 customer-facing eligibility = compatibility + location + availability.

    Used by BLOOD_DONOR request list/detail surfaces so a donor only ever sees
    requests they could actually fulfill (BR-005, C8). Location is compared on
    any provided region/city; blank donor location is treated as "in scope".
    """
    if donor.user_id and request.created_by_id == donor.user_id:
        return False
    if not is_donor_compatible(donor.blood_group, request.blood_group_needed):
        return False
    if not donor.is_available:
        return False
    location = request.location or {}
    region = (location.get("region") or "").strip()
    city = (location.get("city") or "").strip()
    if region and donor.region and donor.region.strip().lower() != region.lower():
        return False
    if city and donor.city and donor.city.strip().lower() != city.lower():
        return False
    return True


def _score(request, donor, *, compatible: bool) -> tuple:
    score = 0.20 if compatible else 0.0
    reasons = []
    if donor.blood_group == request.blood_group_needed:
        score += 0.30
        reasons.append("exact_blood_group")
    elif compatible:
        reasons.append("compatible_blood_group")
    if donor.donation_count:
        score += min(donor.donation_count, 5) * 0.02
        reasons.append("donation_history")
    location = request.location or {}
    region = (location.get("region") or "").strip().lower()
    city = (location.get("city") or "").strip().lower()
    if city and donor.city and donor.city.strip().lower() == city:
        score += 0.10
        reasons.append("same_city")
    elif region and donor.region and donor.region.strip().lower() == region:
        score += 0.05
        reasons.append("same_region")
    if donor.is_available:
        score += 0.15
        reasons.append("available")
    return round(score, 3), reasons


@transaction.atomic
def run_matching(request: BloodRequest):
    """Create SUGGESTED matches for verified, available, compatible donors.

    Idempotent per (request, donor) via the unique constraint. Donors are
    notified once per match (`delivery_key=blood:match:<id>` so re-runs never
    double-notify). The request moves to MATCHING when at least one donor is
    matched (lifecycle: ACTIVE → MATCHING).
    """
    if request.status not in ("ACTIVE",):
        return []
    candidate_groups = RECIPIENT_ACCEPTABLE_DONORS.get(request.blood_group_needed, set())
    donors = (
        BloodDonor.objects.filter(
            is_verified=True,
            is_available=True,
            blood_group__in=candidate_groups,
        )
        .exclude(user_id=request.created_by_id)
        .select_related("user")
    )
    created = []
    for donor in donors:
        if not is_donor_eligible(request, donor):
            continue
        compatible = donor.blood_group != request.blood_group_needed
        score, reasons = _score(request, donor, compatible=compatible)
        try:
            match = BloodMatch.objects.create(
                request=request,
                donor=donor,
                match_score=score,
                match_reason={"factors": reasons},
            )
        except Exception:
            logger.warning("Duplicate match skipped (request=%s donor=%s)", request.pk, donor.pk)
            continue
        create_notification(
            recipient=donor.user,
            type_="BLOOD",
            title="New blood request near you",
            body=(
                f"A {request.units}-unit {request.blood_group_needed} request "
                f"({request.get_urgency_display().lower()}) may need you."
            ),
            related_resource_type="blood_request",
            related_resource_id=str(request.uid),
            delivery_key=f"blood:match:{match.pk}",
        )
        created.append(match)
    if created:
        BloodRequest.objects.filter(pk=request.pk).update(status="MATCHING")
        request.status = "MATCHING"
    return created


def run_matching_for_all():
    """Admin matcher: every ACTIVE request (FR-BLD-008). Returns match counts."""
    counts = {}
    for request in BloodRequest.objects.filter(status="ACTIVE"):
        matches = run_matching(request)
        counts[str(request.uid)] = len(matches)
    return counts


def respond_to_match(match: BloodMatch, donor: BloodDonor, *, accept: bool) -> BloodMatch:
    """Donor accepts/declines a suggested match (C9 own match only, enforced in view).

    Accepting moves the request to MATCHED and notifies the requester; the
    requester then carries the next step through a facility (donation event).
    Rejecting is final for that donor/match pair.
    """
    if match.status not in ("SUGGESTED", "NOTIFIED"):
        raise ValueError("This suggestion is no longer actionable.")
    # Stage 4.20: a terminal-closed request must not accept new donor responses
    # (the request is CANCELLED/REJECTED/FULFILLED/EXPIRED). Previously a donor
    # could ACCEPT after the requester cancelled, leaving a live ACCEPTED match
    # against a closed request with no notification sent.
    if match.request.status not in ("ACTIVE", "MATCHING", "MATCHED"):
        raise ValueError("This request is no longer active.")
    match.status = "ACCEPTED" if accept else "DECLINED"
    match.responded_at = timezone.now()
    match.save(update_fields=["status", "responded_at"])
    request = match.request
    if accept and request.status in ("ACTIVE", "MATCHING"):
        BloodRequest.objects.filter(pk=request.pk).update(status="MATCHED")
        request.status = "MATCHED"
        create_notification(
            recipient=request.created_by,
            type_="BLOOD",
            title="A donor accepted your blood request",
            body=(
                f"A {match.donor.blood_group} donor accepted your request. "
                "Visit the closest verified facility to complete the donation."
            ),
            related_resource_type="blood_request",
            related_resource_id=str(request.uid),
            delivery_key=f"blood:accepted:{match.pk}",
        )
    return match


def record_donation(
    *,
    donor: BloodDonor,
    request: BloodRequest | None,
    facility,
    units: int,
    donated_at,
    outcome: str,
    recorded_by,
    donation_serial: str = "",
) -> BloodRequest | None:
    """Record an IMMUTABLE donation event and, on COMPLETED, fulfill the request
    (request → FULFILLED, its accepted matches → FULFILLED, donor counters updated).

    Returns the (possibly updated) request when one was supplied.
    """
    from .models import BloodDonationEvent

    serial = donation_serial or f"BLD-{timezone.now():%Y%m%d}-{donor.pk}-{donor.donation_count + 1}"
    event = BloodDonationEvent.objects.create(
        donor=donor,
        request=request,
        facility=facility,
        units=units,
        donated_at=donated_at,
        outcome=outcome,
        donation_serial=serial,
        recorded_by=recorded_by,
    )
    if outcome == "COMPLETED":
        donor.last_donation_date = donated_at.date()
        donor.donation_count += 1
        donor.save(update_fields=["last_donation_date", "donation_count"])
        if request is not None:
            BloodRequest.objects.filter(pk=request.pk).update(status="FULFILLED")
            request.status = "FULFILLED"
            BloodMatch.objects.filter(request=request, status="ACCEPTED").update(
                status="FULFILLED", fulfilled_at=timezone.now(),
            )
    return request


def eligible_donor(request: BloodRequest, user) -> bool:
    """Whether `user`'s donor profile could fulfill `request` (C8 helper)."""
    try:
        donor = user.blood_donor_profile
    except BloodDonor.DoesNotExist:
        return False
    return is_donor_eligible(request, donor)