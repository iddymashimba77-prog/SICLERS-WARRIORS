"""Consent authorization service (AUTH-1; database-design §9, role-perm §15/§22).

Enforcement at request time: the grantee's effective permissions are
intersected with the ACTIVE consent `permission_scope`; expiry/revocation are
checked against the DB clock (never client-side). Consent changes/access are
always audited by the views that call these helpers.
"""

from django.utils import timezone

from .models import Consent


def expire_due() -> int:
    """Flip ACTIVE consents past `expires_at` to EXPIRED (DB-clock truth).

    Idempotent; returns the number transitioned. Called lazily at read time so
    an expired grant is never served, without a background job.
    """
    return Consent.objects.filter(status="ACTIVE", expires_at__lte=timezone.now()).update(
        status="EXPIRED"
    )


def active_scope(patient, grantee) -> set[str]:
    """Union of permission codes granted by ACTIVE, non-expired consents.

    ``patient`` is a ``patients.Patient`` row (the grantor). Returns an empty
    set when no live grant covers the pair — deny by default.
    """
    expire_due()
    now = timezone.now()
    codes: set[str] = set()
    rows = Consent.objects.filter(
        patient_profile=patient,
        granted_to=grantee,
        status="ACTIVE",
        start_date__lte=now,
        expires_at__gt=now,
    )
    for row in rows:
        scope = row.permission_scope or []
        if isinstance(scope, (list, tuple)):
            codes.update(str(code) for code in scope)
        elif isinstance(scope, dict):
            codes.update(str(code) for code in scope.values())
    return codes


def can_access(patient, grantee, permission_code: str) -> bool:
    """True when a live consent grants ``permission_code`` to the grantee."""
    return permission_code in active_scope(patient, grantee)


def grant(*, patient, granted_to, permission_scope, resource_type,
          resource_ids=None, purpose="", expires_at=None, start_date=None,
          authorized_role=None):
    """Create an ACTIVE consent (DRAFT→ACTIVE creation per api-design §consent)."""
    now = timezone.now()
    if expires_at is None or expires_at <= now:
        raise ValueError("expires_at must be in the future.")
    if not permission_scope:
        raise ValueError("permission_scope cannot be empty.")
    if start_date is None:
        start_date = now
    row = Consent.objects.create(
        patient_profile=patient,
        granted_to=granted_to,
        authorized_role=authorized_role,
        resource_type=resource_type,
        resource_ids=resource_ids,
        permission_scope=[str(c) for c in permission_scope],
        purpose=purpose,
        start_date=start_date,
        expires_at=expires_at,
        status="ACTIVE",
    )
    return row


def revoke(row: Consent, *, actor) -> Consent:
    """Immediate-effect revocation (FR-MEDREC-005)."""
    if row.status == "REVOKED":
        return row
    row.status = "REVOKED"
    row.revoked_by = actor
    row.revoked_at = timezone.now()
    row.save(update_fields=["status", "revoked_by", "revoked_at", "updated_at"])
    return row


def renew(row: Consent, *, expires_at, actor) -> Consent:
    """Extend expiry on an ACTIVE (or live) consent."""
    if expires_at <= timezone.now():
        raise ValueError("expires_at must be in the future.")
    if row.status not in ("ACTIVE",):
        raise ValueError("Only an active consent can be renewed.")
    row.expires_at = expires_at
    row.save(update_fields=["expires_at", "updated_at"])
    return row