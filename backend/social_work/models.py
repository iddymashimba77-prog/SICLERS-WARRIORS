"""Social-support records for the social-worker workspace (§3).

Casework, needs assessments and referrals — deliberately separate tables
and endpoints from the psychology workspace: the two roles never read each
other's rows, and neither can reach the other's role-gated URLs.

No financial system lives here. ``linked_workflow`` is a *pointer* to an
existing campaign or donation workflow; no money is computed, stored or
moved by this app.
"""
import uuid

from django.conf import settings
from django.db import models

# Needs domains a social worker structures an assessment around.
# Free-text clinical/family detail goes in `notes`; these are the codes.
NEED_CODES_LIST = [
    ("food_security", "Food security"),
    ("transport_to_care", "Transport to care"),
    ("housing_living_situation", "Housing / living situation"),
    ("income_employment", "Income and employment"),
    ("family_caregiving", "Family and caregiving"),
    ("school_work_support", "School or work support"),
    ("social_inclusion", "Social inclusion"),
    ("treatment_adherence", "Treatment adherence support"),
]
NEED_CODES = [code for code, _ in NEED_CODES_LIST]


class SocialCase(models.Model):
    """One social-support case for one patient, opened by one worker."""

    STATUSES = [
        ("NEW", "NEW"),
        ("IN_PROGRESS", "IN_PROGRESS"),
        ("AWAITING_REFERRAL", "AWAITING_REFERRAL"),
        ("RESOLVED", "RESOLVED"),
    ]
    TRANSITIONS = {
        "NEW": ["IN_PROGRESS", "AWAITING_REFERRAL", "RESOLVED"],
        "IN_PROGRESS": ["AWAITING_REFERRAL", "RESOLVED"],
        "AWAITING_REFERRAL": ["IN_PROGRESS", "RESOLVED"],
        "RESOLVED": ["IN_PROGRESS"],  # reopen
    }

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    patient = models.ForeignKey(
        "patients.Patient", on_delete=models.PROTECT, related_name="social_cases",
    )
    opened_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="social_cases_opened",
    )
    title = models.CharField(max_length=200, help_text="Short summary of the situation.")
    status = models.CharField(max_length=24, choices=STATUSES, default="NEW", db_index=True)
    opened_at = models.DateTimeField(db_index=True)
    closed_at = models.DateTimeField(null=True, blank=True)
    linked_workflow = models.CharField(
        max_length=200, blank=True,
        help_text=(
            "Pointer to an existing campaign or donation workflow — this app "
            "never handles money itself."
        ),
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "social_cases"
        ordering = ["-opened_at", "-pk"]

    def __str__(self) -> str:
        return f"SocialCase({self.uid}, {self.status})"


class CaseNote(models.Model):
    """A casework note — the social worker's own words, attached to a case."""

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    case = models.ForeignKey(
        SocialCase, on_delete=models.PROTECT, related_name="notes",
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="social_case_notes_authored",
    )
    note = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "social_case_notes"
        ordering = ["-created_at", "-pk"]

    def __str__(self) -> str:
        return f"CaseNote({self.uid})"


class SocialNeedsAssessment(models.Model):
    """Structured social needs observed for one patient at one point in time.

    No scoring: the worker records which needs are present and their own
    observations — nothing here computes severity or eligibility.
    """

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    patient = models.ForeignKey(
        "patients.Patient", on_delete=models.PROTECT, related_name="social_needs_assessments",
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="social_needs_assessments_authored",
    )
    needs = models.JSONField(
        default=list, help_text="Array of NEED_CODES_LIST codes that apply.",
    )
    observations = models.TextField(blank=True)
    follow_up_at = models.DateTimeField(null=True, blank=True)
    assessed_at = models.DateTimeField(db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "social_needs_assessments"
        ordering = ["-assessed_at", "-pk"]

    def __str__(self) -> str:
        return f"SocialNeedsAssessment({self.uid})"


class SocialReferral(models.Model):
    """A referral to another service, keeping an owner and a follow-up date."""

    URGENCIES = [
        ("ROUTINE", "ROUTINE"),
        ("URGENT", "URGENT"),
        ("IMMEDIATE", "IMMEDIATE"),
    ]
    STATUSES = [
        ("REQUESTED", "REQUESTED"),
        ("ACCEPTED", "ACCEPTED"),
        ("DECLINED", "DECLINED"),
        ("COMPLETED", "COMPLETED"),
        ("CANCELLED", "CANCELLED"),
    ]
    TRANSITIONS = {
        "REQUESTED": ["ACCEPTED", "DECLINED", "CANCELLED"],
        "ACCEPTED": ["COMPLETED", "DECLINED", "CANCELLED"],
        "DECLINED": [],
        "COMPLETED": [],
        "CANCELLED": [],
    }

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    patient = models.ForeignKey(
        "patients.Patient", on_delete=models.PROTECT, related_name="social_referrals",
    )
    case = models.ForeignKey(
        SocialCase, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="referrals",
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="social_referrals_authored",
    )
    destination = models.CharField(max_length=200)
    reason = models.TextField()
    urgency = models.CharField(max_length=16, choices=URGENCIES, default="ROUTINE")
    status = models.CharField(max_length=16, choices=STATUSES, default="REQUESTED", db_index=True)
    responsible_person = models.CharField(
        max_length=200, blank=True,
        help_text="Who owns the next step once the referral is accepted.",
    )
    follow_up_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "social_referrals"
        ordering = ["-created_at", "-pk"]

    def __str__(self) -> str:
        return f"SocialReferral({self.uid}, {self.status})"
