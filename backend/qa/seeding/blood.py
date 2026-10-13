"""Phase 4 — blood network: requests, matches, donation events.

Leaves a realistic verification queue for the admin API phase (15 requests
``PENDING_VERIFICATION``) plus a spread of already-decided/fulfilled requests
with matches and immutable donation events.
"""

from __future__ import annotations

import datetime as _dt

from django.utils import timezone

from accounts.models import User
from blood_network.models import (
    RECIPIENT_ACCEPTABLE_DONORS, BloodDonationEvent, BloodDonor, BloodMatch,
    BloodRequest, BloodRequestDecision,
)
from blood_network.services import record_decision
from patients.models import Patient

from .base import TAG, uuid_for

BLOOD_GROUPS = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]
DECIDED_STATUSES = ["ACTIVE", "MATCHING", "MATCHED", "FULFILLED", "EXPIRED", "CANCELLED"]


def _patients(ctx):
    return list(Patient.objects.filter(user__in=ctx.users_of("PATIENT")))


def _donors(ctx):
    return list(BloodDonor.objects.filter(user__in=ctx.users_of("BLOOD_DONOR")))


def _compatible_donors(group, donors):
    allowed = RECIPIENT_ACCEPTABLE_DONORS.get(group, {group})
    return [d for d in donors if d.blood_group in allowed]


def seed(ctx) -> None:
    ctx.log("## Blood network")
    rng = ctx.rng
    now = timezone.now()
    patients = _patients(ctx)
    donors = _donors(ctx)
    facilities = ctx.all_facilities()
    if not patients or not donors:
        ctx.log("- skipped (need patients + donors)")
        return

    decided_requests = []
    for i, patient in enumerate(patients, start=1):
        group = BLOOD_GROUPS[(i * 3) % len(BLOOD_GROUPS)]
        urgency = ["NORMAL", "URGENT", "CRITICAL"][i % 3]
        if i <= 15:
            status = "PENDING_VERIFICATION"
        else:
            status = DECIDED_STATUSES[i % len(DECIDED_STATUSES)]
        req, _ = BloodRequest.objects.update_or_create(
            uid=uuid_for("blood-request", i),
            defaults={
                "patient": patient.user,
                "created_by": patient.user,
                "blood_group_needed": group,
                "units": 1 + (i % 3),
                "urgency": urgency,
                "facility": rng.choice(facilities) if facilities else None,
                "reason": f"{TAG} demo request for {urgency.lower()} transfusion need.",
                "location": {"region": patient.address_region, "city": patient.address_city},
                "status": status,
                "verified_by": ctx.admin if status != "PENDING_VERIFICATION" else None,
                "verified_at": now - _dt.timedelta(days=3) if status != "PENDING_VERIFICATION" else None,
                "rejection_reason": "",
            },
        )
        ctx.track("blood_requests")
        if status != "PENDING_VERIFICATION":
            decided_requests.append((req, status))
            if not BloodRequestDecision.objects.filter(request=req).exists():
                record_decision(
                    req, decision="VERIFIED", actor=ctx.admin,
                    from_status="PENDING_VERIFICATION", to_status=status,
                    reason=f"{TAG} seeded decision.",
                )

    # Matches + donation events for requests that reached matching/full/active.
    for req, status in decided_requests:
        candidates = _compatible_donors(req.blood_group_needed, donors)
        if not candidates:
            continue
        if status in ("MATCHING", "ACTIVE"):
            for d in candidates[:2]:
                BloodMatch.objects.get_or_create(
                    request=req, donor=d,
                    defaults={
                        "match_score": 0.8 + rng.random() * 0.2,
                        "match_reason": {"blood_group": d.blood_group, "city": d.city},
                        "status": rng.choice(["SUGGESTED", "NOTIFIED", "ACCEPTED"]),
                    },
                )
                ctx.track("blood_matches")
        elif status in ("MATCHED", "FULFILLED"):
            d = candidates[0]
            match, _ = BloodMatch.objects.get_or_create(
                request=req, donor=d,
                defaults={
                    "match_score": 0.95, "match_reason": {"blood_group": d.blood_group},
                    "status": "ACCEPTED" if status == "MATCHED" else "FULFILLED",
                    "notified_at": now - _dt.timedelta(days=2),
                    "responded_at": now - _dt.timedelta(days=2),
                    "fulfilled_at": now - _dt.timedelta(days=1) if status == "FULFILLED" else None,
                },
            )
            ctx.track("blood_matches")
            if status == "FULFILLED":
                BloodDonationEvent.objects.get_or_create(
                    donation_serial=f"{TAG}-DON-REQ-{req.pk}",
                    defaults={
                        "donor": d, "request": req,
                        "facility": req.facility, "units": req.units,
                        "donated_at": now - _dt.timedelta(days=1),
                        "outcome": "COMPLETED", "recorded_by": ctx.admin,
                    },
                )
                ctx.track("donation_events")

    # Standalone donation history so donor profiles show a track record.
    for i, donor in enumerate(donors, start=1):
        for j in range(1, (i % 3) + 1):
            BloodDonationEvent.objects.get_or_create(
                donation_serial=f"{TAG}-DON-{donor.pk}-{j}",
                defaults={
                    "donor": donor,
                    "request": None,
                    "facility": rng.choice(ctx.facilities_of("BLOOD_BANK")) if ctx.facilities_of("BLOOD_BANK") else None,
                    "units": 1,
                    "donated_at": now - _dt.timedelta(days=30 * j),
                    "outcome": "COMPLETED" if j % 4 else "DEFERRED",
                    "recorded_by": ctx.admin,
                },
            )
            ctx.track("donation_events")
        donor.donation_count = BloodDonationEvent.objects.filter(
            donor=donor, outcome="COMPLETED",
        ).count()
        donor.save(update_fields=["donation_count"])

    ctx.log(
        f"- requests={ctx.counts.get('blood_requests', 0)} "
        f"matches={ctx.counts.get('blood_matches', 0)} "
        f"donation_events={ctx.counts.get('donation_events', 0)}"
    )
