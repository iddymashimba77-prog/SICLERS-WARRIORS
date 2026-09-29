"""Stage 4.4 RBAC gate — ephemeral SQLite ONLY (never Postgres).

Purpose
-------
Proves the server-side authorization SSoT that Stage 4.4 ships and that the
role-aware Flutter shell consumes (approved role/permission matrix, §3.3):

  1. /api/auth/register/ with a SELF_REGISTERABLE role (PATIENT) -> 201 +
     a JWT pair (access/refresh) so the mobile client can act immediately.
  2. /api/auth/register/ with a PRIVILEGED role (DOCTOR, SUPER_ADMIN) -> 400
     (privilege-escalation rejected; never self-assignable, §18/§3.3).
  3. /api/auth/me/ returns role_codes + permission_codes (role-aware nav
     contract) and account_status; account_status gates further access.

It runs against the ephemeral SQLite DB (config/settings/ephemeral_test.py,
approved §34 fresh/empty DB strategy). It NEVER contacts Postgres and requires
no superuser / DROP-CREATE. This is the same DB the seed migration 0003 targets.

Run:  venv/bin/python stage44_gate.py   (from backend/)
Expected final line:  GATE_OK
"""

import os
import uuid

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.ephemeral_test")

import django

django.setup()

from django.test.runner import DiscoverRunner

runner = DiscoverRunner(verbosity=0, interactive=False)
old_config = runner.setup_databases()

try:
    from rest_framework.test import APIClient

    c = APIClient()

    email = f"g-{uuid.uuid4().hex[:10]}@example.com"
    s1 = c.post(
        "/api/auth/register/",
        {
            "email": email,
            "password": "Str0ng!Pass9",
            "first_name": "Grace",
            "last_name": "Hopper",
            "role_code": "PATIENT",
        },
        format="json",
    )
    print("register PATIENT:", s1.status_code)
    ok = s1.status_code in (200, 201)
    access = (s1.data or {}).get("access") if hasattr(s1, "data") else None
    print("  access token issued:", bool(access))
    ok = ok and bool(access)

    c.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    me = c.get("/api/auth/me/")
    md = me.data or {}
    print("me:", me.status_code)
    print(
        "  summary:", {k: md.get(k) for k in ("email", "account_status", "role_codes", "permission_codes")}
    )
    ok = ok and me.status_code == 200 and bool(md.get("role_codes"))

    # Privilege escalation must be rejected server-side (never privileged).
    c2 = APIClient()
    s2 = c2.post(
        "/api/auth/register/",
        {
            "email": f"e-{uuid.uuid4().hex[:10]}@example.com",
            "password": "Str0ng!Pass9",
            "first_name": "Eve",
            "last_name": "Mallory",
            "role_code": "SUPER_ADMIN",
        },
        format="json",
    )
    print("self-reg SUPER_ADMIN (expect 400):", s2.status_code)
    ok = ok and s2.status_code == 400

    s3 = c2.post(
        "/api/auth/register/",
        {
            "email": f"d-{uuid.uuid4().hex[:10]}@example.com",
            "password": "Str0ng!Pass9",
            "first_name": "Doc",
            "last_name": "Torus",
            "role_code": "DOCTOR",
        },
        format="json",
    )
    print("self-reg DOCTOR (expect 400):", s3.status_code)
    ok = ok and s3.status_code == 400

finally:
    runner.teardown_databases(old_config)

print("GATE_OK" if ok else "GATE_FAILED")
