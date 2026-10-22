"""Mental-health records for the psychologist workspace (§2).

Every row here is authored by a verified psychologist and read only when a
live consent grants that professional the matching ``psychology.*`` code
(deny by default, like the rest of the platform).

Deliberately **no psychiatric scoring**: an assessment stores structured
psychosocial concerns, a qualitative clinician impression and a risk flag —
never a computed severity score, threshold or diagnosis.
"""
import uuid

from django.conf import settings
from django.db import models

# The concern domains this workspace asks clinicians to structure around.
# Free-text clinical detail goes in `notes`; these are the navigable codes.
CONCERN_DOMAINS = [
    ("coping_with_chronic_illness", "Coping with chronic illness"),
    ("pain_related_distress", "Pain-related distress"),
    ("anxiety_symptoms", "Anxiety symptoms"),
    ("depression_symptoms", "Depression symptoms"),
    ("stigma", "Stigma"),
    ("bullying", "Bullying"),
    ("sleep_difficulties", "Sleep difficulties"),
    ("social_support", "Social support"),
    ("family_relationships", "Family relationships"),
    ("school_challenges", "School challenges"),
    ("workplace_challenges", "Workplace challenges"),
]
CONCERN_CODES = [code for code, _ in CONCERN_DOMAINS]


class PsychAssessment(models.Model):
    """A structured psychosocial assessment of one patient by one author."""

    IMPRESSIONS = [
        ("NONE", "NONE"),
        ("MILD", "MILD"),
        ("MODERATE", "MODERATE"),
        ("SEVERE", "SEVERE"),
    ]
    RISK_LEVELS = [
        ("ROUTINE", "ROUTINE"),
        ("MONITOR", "MONITOR"),
        ("URGENT", "URGENT"),
    ]

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    patient = models.ForeignKey(
        "patients.Patient", on_delete=models.PROTECT, related_name="psych_assessments",
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="psych_assessments_authored",
    )
    concerns = models.JSONField(
        default=list,
        help_text="Array of CONCERN_DOMAINS codes the psychologist selected.",
    )
    impression = models.CharField(max_length=16, choices=IMPRESSIONS, default="NONE")
    risk_level = models.CharField(max_length=16, choices=RISK_LEVELS, default="ROUTINE")
    notes = models.TextField(
        blank=True,
        help_text="Free-text clinical impression — never used to compute a score.",
    )
    assessed_at = models.DateTimeField(db_index=True)
    follow_up_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "psych_assessments"
        ordering = ["-assessed_at", "-pk"]

    def __str__(self) -> str:
        return f"PsychAssessment({self.uid}, {self.risk_level})"


class ProgressNote(models.Model):
    """A counselling session note — the psychologist's own words, one event."""

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    patient = models.ForeignKey(
        "patients.Patient", on_delete=models.PROTECT, related_name="psych_progress_notes",
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="psych_progress_notes_authored",
    )
    note = models.TextField(help_text="Session narrative.")
    session_at = models.DateTimeField(db_index=True)
    follow_up_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "psych_progress_notes"
        ordering = ["-session_at", "-pk"]

    def __str__(self) -> str:
        return f"ProgressNote({self.uid})"


class PsychologyReferral(models.Model):
    """An internal escalation from psychology to another service or role.

    Kept inside the psychology workspace (not shared with social-work
    referrals) so the two roles never read each other's caseloads.
    """

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

    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True, db_index=True)
    patient = models.ForeignKey(
        "patients.Patient", on_delete=models.PROTECT, related_name="psychology_referrals",
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="psychology_referrals_authored",
    )
    destination = models.CharField(
        max_length=200, help_text="Service, facility or role being referred to.",
    )
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
        db_table = "psychology_referrals"
        ordering = ["-created_at", "-pk"]

    def __str__(self) -> str:
        return f"PsychologyReferral({self.uid}, {self.status})"
