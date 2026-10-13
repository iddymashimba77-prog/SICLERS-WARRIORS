"""Phase 2 — caregiver relationships and the consent that authorizes them.

A caregiver link is the *who*; the ``Consent`` row is the *what* (scope +
expiry). Both must be ACTIVE for a caregiver to read patient data, so the seed
creates a realistic mix (active / pending / revoked + matching consents).
"""

from __future__ import annotations

import datetime as _dt

from django.utils import timezone

from accounts.models import Role
from medical_records.models import Consent
from patients.models import CaregiverRelationship, Patient

from .base import TAG

REL_TYPES = ["PARENT", "SPOUSE", "CHILD", "SIBLING", "GUARDIAN", "FRIEND"]
CONSENT_SCOPE = [
    "patients.read", "medical_records.read", "medications.read",
    "symptoms.read", "appointments.read",
]


def _patient_for(user) -> Patient | None:
    return Patient.objects.filter(user=user).first()


def seed(ctx) -> None:
    ctx.log("## Caregiver relationships & consents")
    patients = list(Patient.objects.filter(user__in=ctx.users_of("PATIENT")))
    caregivers = ctx.users_of("CAREGIVER")
    if not patients or not caregivers:
        ctx.log("- skipped (need patients and caregivers)")
        return

    caregiver_role = Role.objects.get(code="CAREGIVER")
    now = timezone.now()

    for i, caregiver in enumerate(caregivers):
        patient = patients[i % len(patients)]
        status = "ACTIVE" if i < len(caregivers) - 5 else ("PENDING" if i % 2 else "REVOKED")
        rel, _ = CaregiverRelationship.objects.update_or_create(
            patient=patient, user=caregiver,
            defaults={
                "relationship_type": REL_TYPES[i % len(REL_TYPES)],
                "status": status,
                "invited_by": patient.user,
                "accepted_at": now - _dt.timedelta(days=10) if status == "ACTIVE" else None,
            },
        )
        ctx.track("caregiver_links")

        if status == "ACTIVE":
            Consent.objects.update_or_create(
                patient_profile=patient,
                granted_to=caregiver,
                resource_type="patients",
                defaults={
                    "authorized_role": caregiver_role,
                    "permission_scope": CONSENT_SCOPE,
                    "purpose": f"{TAG} caregiver access to support a family member.",
                    "start_date": now - _dt.timedelta(days=10),
                    "expires_at": now + _dt.timedelta(days=180),
                    "status": "ACTIVE",
                },
            )
            ctx.track("caregiver_consents_active")
        else:
            Consent.objects.update_or_create(
                patient_profile=patient,
                granted_to=caregiver,
                resource_type="patients",
                defaults={
                    "authorized_role": caregiver_role,
                    "permission_scope": CONSENT_SCOPE,
                    "purpose": f"{TAG} demo caregiver consent (inactive).",
                    "start_date": now - _dt.timedelta(days=30),
                    "expires_at": now - _dt.timedelta(days=1),
                    "status": status if status in ("REVOKED", "DRAFT") else "DRAFT",
                    "revoked_by": caregiver if status == "REVOKED" else None,
                    "revoked_at": now - _dt.timedelta(days=2) if status == "REVOKED" else None,
                },
            )
            ctx.track("caregiver_consents_inactive")
    ctx.log(f"- caregiver links: {ctx.counts.get('caregiver_links', 0)}")
