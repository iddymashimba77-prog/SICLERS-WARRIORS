"""Phase 11 — verify every seeded account can actually sign in.

Uses the real ``POST /api/auth/login/`` endpoint (``email_or_phone`` + password)
so this proves the whole stack — password hash, account status, token issuance —
not just that a row exists. Results are recorded on the context for the report.
"""

from __future__ import annotations

from django.core.cache import cache
from rest_framework.test import APIClient

from .base import TAG


def _role_users(ctx) -> dict:
    """Seeded users grouped by role.

    Prefers the in-memory map the earlier phases populated; falls back to the
    database (grouping tagged accounts by their granted role) so that a
    ``--only login_check`` run still verifies the full dataset.
    """
    if ctx.users:
        return ctx.users
    from accounts.models import UserRole

    groups: dict = {}
    rows = UserRole.objects.filter(
        user__email__startswith=TAG.lower(),
    ).select_related("user", "role")
    for row in rows:
        groups.setdefault(row.role.code, []).append(row.user)
    return groups



def run(ctx, stdout=None) -> None:
    cache.clear()
    client = APIClient()
    results = {}
    failures = []
    total = 0
    ok_total = 0

    for role, users in _role_users(ctx).items():
        ok = 0
        for user in users:
            total += 1
            resp = client.post(
                "/api/auth/login/",
                {"email_or_phone": user.email, "password": ctx.password},
                format="json",
            )
            if resp.status_code == 200 and "access" in getattr(resp, "data", {}):
                ok += 1
                ok_total += 1
            else:
                failures.append(
                    f"{role} {user.email} -> {resp.status_code} {getattr(resp, 'data', '')}"
                )
        results[role] = {"total": len(users), "ok": ok}

    ctx.verified["login"] = {
        "total": total,
        "ok": ok_total,
        "by_role": results,
        "failures": failures,
    }

    line = f"- logins OK: {ok_total}/{total}"
    ctx.log(f"## Login verification\n{line}")
    if stdout:
        stdout.write(f"  → login verification: {ok_total}/{total} OK")
    if failures:
        for failure in failures[:20]:
            ctx.log(f"- FAIL {failure}")
