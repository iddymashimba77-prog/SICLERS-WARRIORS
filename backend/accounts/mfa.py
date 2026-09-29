"""MFA integration boundary (Stage 4.16 — approved §07 auth §MFA / §23).

The approved design mandates step-up authentication (TOTP) for privileged
(admin-ready) roles — api-design.md rows 86-88 (`/auth/mfa/setup|enable|
disable`, gate `auth.mfa_manage`) and special-systems §MFA. The SecurityEvent
vocabulary already defines `MFA_CHALLENGE` / `MFA_FAILED`
(accounts.SecurityEvent.KIND).

What THIS module implements — the *integration boundary*:

* ``MfaPolicy`` — the single security-decision seam: whether an authenticated
  request must carry step-up evidence and whether it currently satisfies the
  policy. 4.16 admin surfaces attach :class:`MfaBoundaryCompliance` so a
  step-up user is refused (403 ``mfa_required``) until verified.
* Security-event recording (``MFA_CHALLENGE`` / ``MFA_FAILED``) when a step-up
  user is refused, so the 4.16 security-events monitoring surface observes it.

What is deliberately NOT implemented here (NOT AVAILABLE): the RFC 6238 TOTP
generation/verification mechanism itself (secret provisioning, challenge
issuance, QR exchange, code verification). Per the stage mandate, we create
the integration boundary — not a second authentication system. Because
``mfa_enabled`` can only become True through that future challenge flow, the
boundary refuses access *before* evidence can exist, which is the honest
contract: enabling MFA on an account has no bypass today.
"""

from typing import TYPE_CHECKING

from django.utils import timezone

if TYPE_CHECKING:  # pragma: no cover — import cycle guard
    from django.http import HttpRequest

    from .models import User

ADMIN_READY_ROLE_CODES = frozenset({"SUPER_ADMIN", "ADMIN"})


def is_admin_ready(user) -> bool:
    """True for authenticated users holding a privileged admin-ready role."""
    return bool(
        user and getattr(user, "is_authenticated", False)
        and getattr(user, "_has_active_role", None)
        and user._has_active_role(*ADMIN_READY_ROLE_CODES)
    )


class MfaPolicy:
    """Step-up decision boundary (4.16). Central, testable, default-deny."""

    def step_up_required(self, user) -> bool:
        """Step-up is owed only when the account has MFA enrolled AND the user
        holds an admin-ready role. Non-admin accounts are out of scope so the
        boundary never degrades general patient access."""
        if not user or not getattr(user, "is_authenticated", False):
            return False
        if not bool(getattr(user, "mfa_enabled", False)):
            return False
        return is_admin_ready(user)

    def is_compliant(self, request, user) -> bool:
        """A step-up request is compliant only if the boundary has evidence.

        Evidence is produced by the TOTP challenge flow (NOT AVAILABLE this
        stage). Until that flow exists no request can be compliant, so every
        `step_up` request is refused — there is no silent MFA bypass.
        """
        if not self.step_up_required(user):
            return True
        return False


_policy = MfaPolicy()


def record_step_up_event(*, user, ip_address=None, event_type="MFA_CHALLENGE"):
    """Best-effort SecurityEvent write (MFA_CHALLENGE / MFA_FAILED).

    Never raises — telemetry must not break the denial of service.
    """
    try:
        from .models import SecurityEvent

        kind = "MFA_FAILED" if event_type == "MFA_FAILED" else "MFA_CHALLENGE"
        if kind not in SecurityEvent.KINDS:
            kind = "MFA_CHALLENGE"
        SecurityEvent.objects.create(
            user=user,
            event_type=kind,
            status="DENIED",
            ip_address=ip_address,
            detail={"reason": "step-up evidence missing", "at": timezone.now().isoformat()},
        )
    except Exception:  # pragma: no cover — defensive by contract
        pass