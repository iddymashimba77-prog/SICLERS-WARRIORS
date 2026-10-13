"""Blood donation & matching domain (approved Stage 4.8).

Source of truth:
  docs/sdlc/03-system-design/erd/blood-emergency-erd.md   (tables + constraints)
  docs/sdlc/03-system-design/database-design.md §8.5      (column specs, CHECK values)
  docs/sdlc/03-system-design/role-permission-matrix.md §3.8 (permission catalog)

CHECK vocabularies (from DB design §8.5, ERD lines 139-140):
  blood_donors.blood_group  : A+ A- B+ B- AB+ AB- O+ O-
  blood_requests.urgency    : NORMAL URGENT CRITICAL
  blood_requests.status     : PENDING_VERIFICATION ACTIVE MATCHING MATCHED FULFILLED
                              EXPIRED CANCELLED REJECTED
  blood_matches.status      : SUGGESTED NOTIFIED ACCEPTED DECLINED FULFILLED EXPIRED
  blood_donation_events.outcome : COMPLETED DEFERRED FAILED

Matching rules (ERD line 290-291):
  "Compatibility + location + availability; donor contact info never public (BR-006)."
  RECIPIENT_ACCEPTABLE_DONORS maps each blood group to the set of donor groups
  that may donate to it — the SSoT for the matching engine.

Ownership model ("deny by default", §18/19):
  * BLOOD_DONOR owns their donor profile + may respond to own matches (C8/C9).
  * PATIENT owns their blood requests (created_by == request.user).
  * Cross-role object access flows through the permission+object rules in §3.8;
    no role gets a blanket backdoor.

IMMUTABLE: blood_donation_events — corrected via compensating records (FR-BLD-010).
"""

import uuid

from django.conf import settings
from django.db import models


BLOOD_GROUPS = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]

# Maps a RECIPIENT blood group → set of donor blood groups that can donate to it.
# SSoT: standard ABO/Rh compatibility (Red Cross consensus).
RECIPIENT_ACCEPTABLE_DONORS = {
    "O-":  {"O-"},
    "O+":  {"O+", "O-"},
    "A-":  {"A-", "O-"},
    "A+":  {"A+", "A-", "O+", "O-"},
    "B-":  {"B-", "O-"},
    "B+":  {"B+", "B-", "O+", "O-"},
    "AB-": {"AB-", "A-", "B-", "O-"},
    "AB+": {"AB+", "AB-", "A+", "A-", "B+", "B-", "O+", "O-"},
}


class BloodDonor(models.Model):
    """Donor profile — 1:1 with User (approved ERD line 124)."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name="blood_donor_profile",
    )
    blood_group = models.CharField(
        max_length=5,
        choices=[(g, g) for g in BLOOD_GROUPS],
    )
    region = models.CharField(max_length=100, blank=True)
    city = models.CharField(max_length=100, blank=True)
    is_available = models.BooleanField(default=True)
    last_donation_date = models.DateField(null=True, blank=True)
    donation_count = models.PositiveIntegerField(default=0)
    is_verified = models.BooleanField(default=False)
    verified_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="verified_blood_donors",
    )
    verified_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "blood_donors"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(blood_group__in=BLOOD_GROUPS),
                name="blood_donor_group_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["blood_group", "city", "is_available"], name="bld_donor_match_idx"),
            # Stage 4.18: donor directory lists verified donors ordered by
            # donation count — this composite serves that filter+sort directly.
            models.Index(fields=["is_verified", "-donation_count"], name="bld_donor_verified_cnt_idx"),
        ]

    def __str__(self):
        return f"Donor({self.user_id}:{self.blood_group})"


BLOOD_REQUEST_STATUSES = ["PENDING_VERIFICATION", "ACTIVE", "MATCHING", "MATCHED",
                          "FULFILLED", "EXPIRED", "CANCELLED", "REJECTED"]


class BloodRequest(models.Model):
    """Blood request — created by a patient/admin, public when verified (BR-005)."""

    URGENCY = [
        ("NORMAL", "NORMAL"),
        ("URGENT", "URGENT"),
        ("CRITICAL", "CRITICAL"),
    ]
    STATUS = [
        ("PENDING_VERIFICATION", "PENDING_VERIFICATION"),
        ("ACTIVE", "ACTIVE"),
        ("MATCHING", "MATCHING"),
        ("MATCHED", "MATCHED"),
        ("FULFILLED", "FULFILLED"),
        ("EXPIRED", "EXPIRED"),
        ("CANCELLED", "CANCELLED"),
        ("REJECTED", "REJECTED"),
    ]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    patient = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="blood_requests",
        help_text="Patient user (if requester is a patient).",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="created_blood_requests",
    )
    blood_group_needed = models.CharField(
        max_length=5, choices=[(g, g) for g in BLOOD_GROUPS],
    )
    units = models.PositiveSmallIntegerField(default=1)
    urgency = models.CharField(max_length=10, choices=URGENCY, default="NORMAL")
    facility = models.ForeignKey(
        "facilities.Facility", null=True, blank=True,
        on_delete=models.SET_NULL, related_name="blood_requests",
    )
    reason = models.TextField(blank=True)
    location = models.JSONField(default=dict, blank=True)
    status = models.CharField(max_length=24, choices=STATUS, default="PENDING_VERIFICATION", db_index=True)
    verified_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="verified_blood_requests",
    )
    verified_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.TextField(blank=True)
    # Idempotency-Key (approved §30): duplicate key → 409, no double request.
    idempotency_key = models.CharField(max_length=120, null=True, blank=True, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "blood_requests"
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(blood_group_needed__in=BLOOD_GROUPS),
                name="bldreq_group_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(urgency__in=["NORMAL", "URGENT", "CRITICAL"]),
                name="bldreq_urgency_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(status__in=BLOOD_REQUEST_STATUSES),
                name="bldreq_status_ck",
            ),
            models.CheckConstraint(
                condition=models.Q(units__gte=1),
                name="bldreq_units_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["status", "urgency"], name="bldreq_status_urg_idx"),
            models.Index(fields=["blood_group_needed", "status"], name="bldreq_grp_status_idx"),
        ]

    def __str__(self):
        return f"BloodRequest({self.uid}:{self.blood_group_needed} [{self.status}])"


class BloodMatch(models.Model):
    """Matching suggestion — links request ↔ donor with score/reason (§ blood_matches)."""

    STATUS = [
        ("SUGGESTED", "SUGGESTED"),
        ("NOTIFIED", "NOTIFIED"),
        ("ACCEPTED", "ACCEPTED"),
        ("DECLINED", "DECLINED"),
        ("FULFILLED", "FULFILLED"),
        ("EXPIRED", "EXPIRED"),
    ]

    request = models.ForeignKey(BloodRequest, on_delete=models.CASCADE, related_name="matches")
    donor = models.ForeignKey(BloodDonor, on_delete=models.CASCADE, related_name="matches")
    match_score = models.DecimalField(max_digits=6, decimal_places=3, default=0)
    match_reason = models.JSONField(default=dict, blank=True)
    status = models.CharField(max_length=12, choices=STATUS, default="SUGGESTED", db_index=True)
    notified_at = models.DateTimeField(null=True, blank=True)
    responded_at = models.DateTimeField(null=True, blank=True)
    fulfilled_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "blood_matches"
        constraints = [
            models.UniqueConstraint(fields=["request", "donor"], name="bld_match_req_donor_uk"),
            models.CheckConstraint(
                condition=models.Q(status__in=[
                    "SUGGESTED", "NOTIFIED", "ACCEPTED", "DECLINED", "FULFILLED", "EXPIRED",
                ]),
                name="bldmatch_status_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["request", "status"], name="bldmatch_req_status_idx"),
        ]

    def __str__(self):
        return f"Match({self.request_id}→{self.donor_id}:{self.status})"


class BloodDonationEvent(models.Model):
    """Immutable donation record (FR-BLD-010: no update/delete). Corrected via compensating records."""

    OUTCOME = [
        ("COMPLETED", "COMPLETED"),
        ("DEFERRED", "DEFERRED"),
        ("FAILED", "FAILED"),
    ]

    donor = models.ForeignKey(BloodDonor, on_delete=models.PROTECT, related_name="donation_events")
    request = models.ForeignKey(
        BloodRequest, null=True, blank=True,
        on_delete=models.PROTECT, related_name="donation_events",
    )
    facility = models.ForeignKey(
        "facilities.Facility", null=True, blank=True,
        on_delete=models.SET_NULL, related_name="donation_events",
    )
    units = models.PositiveSmallIntegerField(default=1)
    donated_at = models.DateTimeField()
    outcome = models.CharField(max_length=10, choices=OUTCOME)
    donation_serial = models.CharField(max_length=100, unique=True)
    recorded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="recorded_blood_donations",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "blood_donation_events"
        ordering = ["-donated_at"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(outcome__in=["COMPLETED", "DEFERRED", "FAILED"]),
                name="bldevent_outcome_ck",
            ),
        ]
        indexes = [
            models.Index(fields=["donor", "-donated_at"], name="bld_donor_donated_idx"),
        ]

    def __str__(self):
        return f"Donation({self.donation_serial}:{self.outcome})"


class AppendOnlyDecisionQuerySet(models.QuerySet):
    """Refuses bulk mutation of a decision history.

    Same reasoning as `audit.AuditLog` and `medical_records.MedicalRecordEvent`:
    instance-level `save()`/`delete()` guards are not enough, because
    `QuerySet.update()` and `QuerySet.delete()` bypass them. A decision trail
    that a single `.filter(...).delete()` can erase is not a decision trail.
    """

    def delete(self):
        raise ValueError("Decision history is append-only and cannot be deleted.")

    def update(self, **kwargs):
        raise ValueError("Decision history is append-only and cannot be modified.")


class BloodRequestDecision(models.Model):
    """APPEND-ONLY decision history for a blood request (FR-BLD-011, BR-005).

    `BloodRequest` keeps only the *latest* decision in its own columns
    (`status`, `verified_by`, `verified_at`, `rejection_reason`), which means a
    row carries no memory of how it got there. This table is that memory: every
    submission, verification, rejection, cancellation, matching round and
    fulfilment is one immutable row, in order, with the actor who decided.

    Why it matters beyond bookkeeping: a rejected request can be resubmitted and
    re-decided, and an approver must be able to show *why* on the earlier attempt.
    Overwriting a single status column destroys that.

    `reason` is free text written by the decider and is allowed to be clinical —
    it is the decider's own justification, not the patient's record. `details`
    stays non-PHI (codes, counts, ids).
    """

    DECISION = [
        ("SUBMITTED", "SUBMITTED"),
        ("VERIFIED", "VERIFIED"),
        ("REJECTED", "REJECTED"),
        ("CANCELLED", "CANCELLED"),
        ("MATCHING_STARTED", "MATCHING_STARTED"),
        ("MATCHED", "MATCHED"),
        ("DONATION_RECORDED", "DONATION_RECORDED"),
        ("FULFILLED", "FULFILLED"),
        ("EXPIRED", "EXPIRED"),
        ("NOTE", "NOTE"),
    ]
    DECISIONS = [value for value, _ in DECISION]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    request = models.ForeignKey(
        BloodRequest, on_delete=models.PROTECT, related_name="decisions",
        help_text="PROTECT: a decision history that loses its subject is useless.",
    )
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="blood_request_decisions",
    )
    decision = models.CharField(max_length=20, choices=DECISION, db_index=True)
    from_status = models.CharField(max_length=24, blank=True)
    to_status = models.CharField(max_length=24, blank=True)
    reason = models.TextField(blank=True)
    details = models.JSONField(default=dict, blank=True)
    decided_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "blood_request_decisions"
        ordering = ["-decided_at", "-pk"]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(decision__in=[
                    "SUBMITTED", "VERIFIED", "REJECTED", "CANCELLED",
                    "MATCHING_STARTED", "MATCHED", "DONATION_RECORDED",
                    "FULFILLED", "EXPIRED", "NOTE",
                ]),
                name="bldreq_decisions_decision_ck",
            ),
        ]
        indexes = [
            models.Index(
                fields=["request", "-decided_at"], name="bldreq_dec_req_time_idx",
            ),
            models.Index(fields=["decision", "-decided_at"], name="bldreq_dec_type_idx"),
        ]

    objects = AppendOnlyDecisionQuerySet.as_manager()

    def __str__(self):
        return f"Decision({self.request_id}:{self.decision})"

    def save(self, *args, **kwargs):
        if self.pk is not None:
            raise ValueError("BloodRequestDecision is append-only and cannot be modified.")
        return super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ValueError("BloodRequestDecision is append-only and cannot be deleted.")
