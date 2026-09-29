#!/usr/bin/env python
"""POSTGRES gate for Stage 4.5 — proof against the REAL dev DB.

Runs the full profile flow on `sickle_cell` (config.settings + .env) and
ROLLS BACK, leaving the DB untouched. Run from backend/:

    venv/bin/python postgres_smoke.py

NOTE: this is the only check that intentionally touches Postgres; the
ephemeral stage gates (stage44/45_gate.py) stay SQLite-only by design.
"""
import json
import os
import sys

import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

from django.db import transaction  # noqa: E402
from django.test import Client  # noqa: E402

from accounts.models import SecurityEvent  # noqa: E402

ok = True


def check(label, got, want):
    global ok
    good = got == want
    ok = ok and good
    print(f"  {label}: got={got!r} want={want!r} -> {'PASS' if good else 'FAIL'}")


def make_user(c, email, phone, role):
    r = c.post(
        "/api/auth/register/",
        data=json.dumps({
            "email": email, "password": "Str0ngPass!9", "phone": phone,
            "full_name": f"PG {role}", "role_code": role,
        }),
        content_type="application/json",
    )
    assert r.status_code == 201, r.content[:300]
    login = c.post(
        "/api/auth/login/",
        data=json.dumps({"email_or_phone": phone, "password": "Str0ngPass!9"}),
        content_type="application/json",
    )
    assert login.status_code == 200, login.content[:300]
    return json.loads(login.content)["data"]["access"]


with transaction.atomic():
    sid = transaction.savepoint()
    try:
        base = "pg-gate@sw.local"
        c = Client()
        tok = make_user(c, base, "+255700000001", "PATIENT")

        r = c.get("/api/auth/me/", HTTP_AUTHORIZATION=f"Bearer {tok}")
        me = json.loads(r.content)["data"]
        check("me role_codes", me.get("role_codes"), ["PATIENT"])
        check("me has patients.update_own", "patients.update_own" in me.get("permission_codes", []), True)

        r = c.get("/api/patients/me/", HTTP_AUTHORIZATION=f"Bearer {tok}")
        check("GET /patients/me", r.status_code, 200)

        r = c.patch(
            "/api/patients/me/",
            data=json.dumps({
                "date_of_birth": "2000-05-14", "gender": "FEMALE", "genotype": "SS",
                "primary_diagnosis": "Sickle Cell Anaemia", "address_region": "Dar es Salaam",
            }),
            content_type="application/json", HTTP_AUTHORIZATION=f"Bearer {tok}",
        )
        check("PATCH /patients/me", r.status_code, 200)
        check("PATCH stores genotype", json.loads(r.content)["data"].get("genotype"), "SS")

        r = c.patch(
            "/api/patients/me/",
            data=json.dumps({"genotype": "ZZ"}),
            content_type="application/json", HTTP_AUTHORIZATION=f"Bearer {tok}",
        )
        check("PATCH bad genotype", r.status_code, 400)

        cg = Client()
        cg_tok = make_user(cg, "pg-gate-cg@sw.local", "+255700000002", "CAREGIVER")
        r = cg.get("/api/patients/me/", HTTP_AUTHORIZATION=f"Bearer {cg_tok}")
        check("CAREGIVER GET /patients/me", r.status_code, 403)

        audits = set(
            SecurityEvent.objects
            .filter(user__email__startswith="pg-gate")
            .values_list("event_type", flat=True)
        )
        check("audit coverage", {"LOGIN_SUCCESS", "PROFILE_CREATED", "PROFILE_UPDATED", "REGISTER"} <= audits, True)
    finally:
        transaction.savepoint_rollback(sid)

print("GATE_OK" if ok else "GATE_FAIL")
sys.exit(0 if ok else 1)