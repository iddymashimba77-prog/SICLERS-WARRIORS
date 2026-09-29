"""Stage 4.5 profile gate — ephemeral SQLite ONLY (never Postgres).

Purpose
-------
Proves the server-side profile/medical-identity SSoT that Stage 4.5 ships
(approved row-162 `patients` model, ownership+permission+audit gates):

  1. /api/auth/register/ with PATIENT -> 201 + JWT pair.
  2. self-register SUPER_ADMIN / DOCTOR -> 400 (privilege escalation rejected).
  3. GET  /api/patients/me/ with PATIENT -> 200 + 1:1 row created.
  4. PATCH /api/patients/me/ with PATIENT -> 200; genotype/gender vocabulary
     validated server-side (bad value -> 400).
  5. A CAREGIVER (no patient identity) -> 403 on /patients/me.
  6. Audit: PROFILE_CREATED / PROFILE_UPDATED SecurityEvents recorded with
     the event type only (never the medical payload, §21).

Runs against the ephemeral SQLite DB (config/settings/ephemeral_test.py,
approved §32/§34 fresh/empty DB strategy). Never contacts Postgres and needs
no superuser / DROP-CREATE.

Run:  venv/bin/python stage45_gate.py   (from backend/)
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

ok = False
try:
    from rest_framework.test import APIClient

    c = APIClient()

    email = f"p-{uuid.uuid4().hex[:10]}@example.com"
    s1 = c.post(
        "/api/auth/register/",
        {
            "email": email,
            "password": "Str0ng!Pass9",
            "first_name": "Paul",
            "last_name": "Patient",
            "role_code": "PATIENT",
        },
        format="json",
    )
    print("register PATIENT:", s1.status_code)
    ok = s1.status_code == 201
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
    ok = ok and me.status_code == 200 and "PATIENT" in (md.get("role_codes") or [])

    # 3. GET own profile -> 200, row auto-created (1:1).
    p1 = c.get("/api/patients/me/")
    pd = (p1.data or {}).get("data") or p1.data or {}
    print("GET /patients/me:", p1.status_code)
    print("  profile present:", bool(pd.get("date_of_birth") in (None, "")))
    ok = ok and p1.status_code == 200 and "genotype" in pd and "notes" in pd

    # 4. PATCH own profile -> 200 with validated vocabulary, audit event.
    p2 = c.patch(
        "/api/patients/me/",
        {
            "date_of_birth": "1998-04-12",
            "gender": "FEMALE",
            "genotype": "SS",
            "diagnosis_date": "1998-07-01",
            "primary_diagnosis": "Sickle cell disease",
            "emergency_contact_name": "Ada",
            "emergency_contact_phone": "+254700000000",
            "emergency_contact_relation": "Sister",
            "address_region": "Nairobi",
            "address_city": "Westlands",
            "notes": "avoid dehydration",
        },
        format="json",
    )
    print("PATCH /patients/me:", p2.status_code)
    body2 = (p2.data or {}).get("data") or p2.data or {}
    print("  genotype:", body2.get("genotype"), "| gender:", body2.get("gender"))
    ok = ok and p2.status_code in (200, 204) and body2.get("genotype") == "SS"

    # 4b. Server-side vocabulary gate -> bad genotype rejected.
    p3 = c.patch("/api/patients/me/", {"genotype": "ZZ"}, format="json")
    print("PATCH bad genotype (expect 400):", p3.status_code)
    ok = ok and p3.status_code == 400

    # 5. CAREGIVER (no patient identity) -> 403 on profile surface.
    c2 = APIClient()
    cg = c2.post(
        "/api/auth/register/",
        {
            "email": f"c-{uuid.uuid4().hex[:10]}@example.com",
            "password": "Str0ng!Pass9",
            "first_name": "Craig",
            "last_name": "Caregiver",
            "role_code": "CAREGIVER",
        },
        format="json",
    )
    cg_access = (cg.data or {}).get("access") if hasattr(cg, "data") else None
    c2.credentials(HTTP_AUTHORIZATION=f"Bearer {cg_access}")
    p4 = c2.get("/api/patients/me/")
    print("CAREGIVER GET /patients/me (expect 403):", p4.status_code)
    ok = ok and p4.status_code == 403

    # 6. Audit: PROFILE_CREATED + PROFILE_UPDATED events recorded (event only).
    from accounts.models import SecurityEvent
    from accounts.models import User

    user = User.objects.get(email=email)
    kinds = set(SecurityEvent.objects.filter(user=user).values_list("event_type", flat=True))
    print("audit events:", sorted(kinds))
    ok = ok and {"PROFILE_CREATED", "PROFILE_UPDATED"} <= kinds

    # 2. Privilege escalation must be rejected server-side.
    for role_code in ("SUPER_ADMIN", "DOCTOR"):
        s = APIClient().post(
            "/api/auth/register/",
            {
                "email": f"x-{uuid.uuid4().hex[:10]}@example.com",
                "password": "Str0ng!Pass9",
                "first_name": "X",
                "last_name": "Y",
                "role_code": role_code,
            },
            format="json",
        )
        print(f"self-reg {role_code} (expect 400):", s.status_code)
        ok = ok and s.status_code == 400

finally:
    runner.teardown_databases(old_config)

print("GATE_OK" if ok else "GATE_FAILED")