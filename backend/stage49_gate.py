"""Stage 4.9 emergency & SOS gate — ephemeral SQLite ONLY.

Purpose
-------
Proves the Stage 4.9 emergency/SOS additions end to end on top of the Stage 4.8
surface (`stage48_gate.py`):

  1. register PATIENT; create HOSPITAL + ADMIN via ORM.
  2. emergency create -> 201 with a bounded C10 grant.
  3. location payload validation: out-of-range / lone coordinate -> 400.
  4. operator/system validate -> VALIDATING; re-validate -> 400.
  5. respond -> RESPONDING; owner detail exposes the responder timeline with
     NO responder PII; the read is audited (emergency_requests.view).
  6. security: anonymous detail -> 401; foreign patient validate -> 403.
  7. patient access-grants -> 200 with an ACTIVE bounded grant.
  8. ADMIN monitoring feed -> 200.
  9. resolve -> RESOLVED and the grant expires.

Run:  venv/bin/python stage49_gate.py   (from backend/)
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
    from django.core.cache import cache
    from rest_framework.test import APIClient
    from rest_framework_simplejwt.tokens import RefreshToken

    from accounts.models import Role, User, UserRole
    from audit.models import AuditLog

    cache.clear()

    def unwrap(resp):
        d = resp.data or {}
        if isinstance(d, dict) and "data" in d:
            return d["data"]
        return d

    def register(role, first="Test", last="User"):
        client = APIClient()
        resp = client.post(
            "/api/auth/register/",
            {
                "email": f"{role.lower()}-{uuid.uuid4().hex[:10]}@example.com",
                "password": "Str0ng!Pass9",
                "first_name": first,
                "last_name": last,
                "role_code": role,
            },
            format="json",
        )
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {(resp.data or {}).get('access')}")
        return client, resp

    def orm_user(role_code):
        user = User.objects.create_user(
            email=f"{role_code.lower()}-{uuid.uuid4().hex[:10]}@example.com",
            password="Str0ng!Pass9",
            first_name="Gate",
            last_name=role_code.title(),
            account_status="ACTIVE",
        )
        UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
        return client, user

    patient, preg = register("PATIENT", "Paul", "Patient")
    hospital_client, _ = orm_user("HOSPITAL")
    admin_client, _ = orm_user("ADMIN")
    ok = preg.status_code == 201
    print("register PATIENT:", preg.status_code)

    payload = {
        "severity": "CRITICAL",
        "type": "PAIN_CRISIS",
        "location": {"city": "Accra"},
        "description": "Stage 4.9 gate crisis",
        "idempotency_key": "gate49-emg-1",
    }
    emg = patient.post("/api/emergency/requests/", payload, format="json")
    emg_uid = unwrap(emg).get("uid")
    print("POST /emergency/requests:", emg.status_code, "| uid:", bool(emg_uid))
    ok = ok and emg.status_code == 201 and bool(emg_uid)

    # --- Location payload validation (EMG-003) ------------------------------
    bad = patient.post(
        "/api/emergency/requests/",
        {"severity": "NORMAL", "type": "OTHER", "location": {"latitude": 100, "longitude": 0}},
        format="json",
    )
    lone = patient.post(
        "/api/emergency/requests/",
        {"severity": "NORMAL", "type": "OTHER", "location": {"latitude": 5.6}},
        format="json",
    )
    print("bad coords (expect 400):", bad.status_code, "| lone coord (expect 400):", lone.status_code)
    ok = ok and bad.status_code == 400 and lone.status_code == 400

    # --- Validate transition (operator/system) ------------------------------
    validated = hospital_client.post(
        f"/api/emergency/requests/{emg_uid}/validate/", {}, format="json"
    )
    print("HOSPITAL validate:", validated.status_code, "| status:", unwrap(validated).get("status"))
    ok = ok and validated.status_code == 200 and unwrap(validated).get("status") == "VALIDATING"

    revalidate = hospital_client.post(
        f"/api/emergency/requests/{emg_uid}/validate/", {}, format="json"
    )
    print("re-validate (expect 400):", revalidate.status_code)
    ok = ok and revalidate.status_code == 400

    responded = hospital_client.post(
        f"/api/emergency/requests/{emg_uid}/respond/", {"role": "ADMIN"}, format="json"
    )
    print("HOSPITAL respond:", responded.status_code, "| status:", unwrap(responded).get("status"))
    ok = ok and responded.status_code == 200 and unwrap(responded).get("status") == "RESPONDING"

    # --- Detail: responder timeline, no PII, audited (FR-EMG-006) -----------
    detail = patient.get(f"/api/emergency/requests/{emg_uid}/")
    body = unwrap(detail)
    responders = body.get("responders", [])
    no_pii = all("responder_email" not in r for r in responders)
    print(
        "GET detail:", detail.status_code,
        "| responders:", len(responders),
        "| no responder PII:", no_pii,
    )
    ok = ok and detail.status_code == 200 and len(responders) == 1 and no_pii
    viewed = AuditLog.objects.filter(action_code="emergency_requests.view").count()
    print("audit emergency_requests.view:", viewed)
    ok = ok and viewed >= 1

    # --- Security -----------------------------------------------------------
    anon = APIClient()
    anon_detail = anon.get(f"/api/emergency/requests/{emg_uid}/")
    stranger, _ = register("PATIENT", "Zed", "Zero")
    foreign = stranger.post(
        f"/api/emergency/requests/{emg_uid}/validate/", {}, format="json"
    )
    print("anonymous detail (expect 401):", anon_detail.status_code,
          "| foreign validate (expect 403):", foreign.status_code)
    ok = ok and anon_detail.status_code == 401 and foreign.status_code == 403

    # --- Access grants (EMG-006) -------------------------------------------
    grants = patient.get("/api/emergency/access-grants/")
    g_data = unwrap(grants)
    active_grants = [
        g for g in (g_data.get("results", []) if isinstance(g_data, dict) else [])
        if g.get("status") == "ACTIVE"
    ]
    print("GET access-grants:", grants.status_code, "| active:", len(active_grants))
    ok = ok and grants.status_code == 200 and len(active_grants) == 1

    # --- Admin monitoring ---------------------------------------------------
    feed = admin_client.get("/api/admin/emergency/")
    feed_uids = {r.get("uid") for r in unwrap(feed)} if feed.status_code == 200 else set()
    print("ADMIN monitoring:", feed.status_code, "| contains request:", emg_uid in feed_uids)
    ok = ok and feed.status_code == 200 and emg_uid in feed_uids

    # --- Resolve + grant expiry --------------------------------------------
    resolved = hospital_client.post(
        f"/api/emergency/requests/{emg_uid}/resolve/", {}, format="json"
    )
    print("HOSPITAL resolve:", resolved.status_code, "| status:", unwrap(resolved).get("status"))
    ok = ok and resolved.status_code == 200 and unwrap(resolved).get("status") == "RESOLVED"

    grants_after = patient.get("/api/emergency/access-grants/")
    after_data = unwrap(grants_after)
    still_active = [
        g for g in (after_data.get("results", []) if isinstance(after_data, dict) else [])
        if g.get("status") == "ACTIVE"
    ]
    print("active grants after resolve (expect 0):", len(still_active))
    ok = ok and len(still_active) == 0

finally:
    runner.teardown_databases(old_config)

print("GATE_OK" if ok else "GATE_FAILED")
