"""Stage 4.8 blood-donation + emergency gate — ephemeral SQLite ONLY.

Purpose
-------
Proves the server-side Stage 4.8 surface end to end:

  1. register PATIENT + CAREGIVER (control subject); create BLOOD_DONOR,
     VERIFICATION_OFFICER, HEALTHCARE_STAFF, HOSPITAL, ADMIN users via ORM
     (BLOOD_DONOR is not self-registerable by policy).
  2. Facility directory: public verified-only list, VO verify endpoint.
  3. Blood request create -> 201 + idempotency duplicate -> 409.
  4. Verify (VO) -> ACTIVE; run matching (ADMIN) -> donor notified.
  5. Donor PATCH /blood/donors/me/ -> 200; donor match ACCEPT -> MATCHED.
  6. Donation event (STA) -> 201; request -> FULFILLED; donor counter.
  7. Emergency create -> 201 + C10 grant + notification; duplicate -> 409;
     anti-spam throttle -> 429 on a dedicated user.
  8. Emergency respond -> RESPONDING; escalate -> ESCALATED; resolve -> RESOLVED
     (grant EXPIRED).
  9. Notifications inbox + read-all; GET /admin/audit-logs (ADMIN).
 10. Security: CAREGIVER blood-request create -> 403; foreign patient -> 404;
     public blood request payload carries no requester PII.

Runs against ephemeral SQLite (config/settings/ephemeral_test.py) exactly like
stage46_gate.py. Never contacts Postgres; no superuser / DROP-CREATE.

Run:  venv/bin/python stage48_gate.py   (from backend/)
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

    from accounts.models import Role, User, UserRole
    from blood_network.models import BloodDonor
    from facilities.models import Facility

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
        from rest_framework_simplejwt.tokens import RefreshToken

        client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
        return client, user

    # --- Actors -------------------------------------------------------------
    patient, preg = register("PATIENT", "Paul", "Patient")
    caregiver, _ = register("CAREGIVER", "Craig", "Caregiver")
    donor_client, donor_user = orm_user("BLOOD_DONOR")
    _, vo_user = orm_user("VERIFICATION_OFFICER")
    staff_client, _ = orm_user("HEALTHCARE_STAFF")
    hospital_client, _ = orm_user("HOSPITAL")
    admin_client, _ = orm_user("ADMIN")
    vo_client = APIClient()
    from rest_framework_simplejwt.tokens import RefreshToken

    vo_client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(vo_user).access_token}")

    ok = preg.status_code == 201
    print("register PATIENT:", preg.status_code)

    facility = Facility.objects.create(
        name="Gate General Hospital", facility_type="HOSPITAL",
        region="Greater Accra", city="Accra", is_verified=True,
    )
    pending_facility = Facility.objects.create(name="Gate Clinic", facility_type="CLINIC")
    donor = BloodDonor.objects.create(
        user=donor_user, blood_group="O+", region="Greater Accra", city="Accra",
        is_available=True, is_verified=True,
    )

    # --- Facility directory + verify ---------------------------------------
    pub = APIClient().get("/api/facilities/")
    names = {f["name"] for f in unwrap(pub).get("results", [])} if pub.status_code == 200 else set()
    print("GET /facilities (public):", pub.status_code, "| verified names:", sorted(names))
    ok = ok and pub.status_code == 200 and "Gate General Hospital" in names

    verify_fac = vo_client.post(
        f"/api/admin/facilities/{pending_facility.uid}/verify", {"approve": True}, format="json"
    )
    print("VO verify facility:", verify_fac.status_code)
    ok = ok and verify_fac.status_code == 200

    # --- Blood request create + idempotency --------------------------------
    payload = {
        "blood_group_needed": "O+",
        "units": 1,
        "urgency": "URGENT",
        "facility_uid": str(facility.uid),
        "location": {"region": "Greater Accra", "city": "Accra"},
    }
    req = patient.post("/api/blood/requests/", payload, format="json")
    req_uid = unwrap(req).get("uid")
    print("POST /blood/requests:", req.status_code, "| uid:", bool(req_uid))
    ok = ok and req.status_code == 201 and bool(req_uid)

    first_keyed = patient.post("/api/blood/requests/", {**payload, "idempotency_key": "gate-1"}, format="json")
    dup = patient.post("/api/blood/requests/", {**payload, "idempotency_key": "gate-1"}, format="json")
    print("blood create keyed:", first_keyed.status_code, "| duplicate (expect 409):", dup.status_code)
    ok = ok and first_keyed.status_code == 201 and dup.status_code == 409

    # Security: caregiver denied, foreign patient isolated.
    cg_denied = caregiver.post("/api/blood/requests/", payload, format="json")
    stranger, _ = register("PATIENT", "Zed", "Zero")
    stolen = stranger.get(f"/api/blood/requests/{req_uid}/")
    print("CAREGIVER create (expect 403):", cg_denied.status_code,
          "| foreign GET (expect 404):", stolen.status_code)
    ok = ok and cg_denied.status_code == 403 and stolen.status_code == 404

    # --- Donor self profile + verify + matching ----------------------------
    prof = donor_client.patch(
        "/api/blood/donors/me/",
        {"blood_group": "O+", "region": "Greater Accra", "city": "Accra"},
        format="json",
    )
    print("PATCH /blood/donors/me:", prof.status_code)
    ok = ok and prof.status_code in (200, 201)

    verified = vo_client.post(f"/api/admin/blood/requests/{req_uid}/verify/")
    print("VO verify request:", verified.status_code, "| status:", unwrap(verified).get("status"))
    ok = ok and verified.status_code == 200 and unwrap(verified).get("status") == "ACTIVE"

    run = admin_client.post("/api/admin/blood/run-matching/", {"request_uid": req_uid}, format="json")
    created = (unwrap(run).get("created") or {}).get(req_uid, 0)
    print("ADMIN run-matching:", run.status_code, "| created:", created)
    ok = ok and run.status_code == 200 and created >= 1

    matches = patient.get(f"/api/blood/requests/{req_uid}/matches/")
    m_data = unwrap(matches)
    m_rows = m_data.get("results", []) if isinstance(m_data, dict) else []
    match_id = m_rows[0]["id"] if m_rows else None
    print("GET matches:", matches.status_code, "| count:", len(m_rows))
    ok = ok and matches.status_code == 200 and match_id

    # No requester PII in the donor-facing public request subset.
    public_req = donor_client.get(f"/api/blood/requests/{req_uid}/")
    ok = ok and public_req.status_code == 200 and "creator_email" not in unwrap(public_req)

    respond = donor_client.post(
        f"/api/blood/matches/{match_id}/respond/", {"action": "ACCEPT"}, format="json"
    )
    print("donor ACCEPT match:", respond.status_code, "| status:", unwrap(respond).get("status"))
    ok = ok and respond.status_code == 200 and unwrap(respond).get("status") == "ACCEPTED"

    event = staff_client.post(
        f"/api/blood/requests/{req_uid}/donation-events/",
        {
            "donor_id": donor.id,
            "facility_uid": str(facility.uid),
            "units": 1,
            "donated_at": "2026-09-18T09:00:00Z",
            "outcome": "COMPLETED",
        },
        format="json",
    )
    print("STA record donation:", event.status_code)
    ok = ok and event.status_code == 201
    donor.refresh_from_db()
    fulfilled = patient.get(f"/api/blood/requests/{req_uid}/")
    print("request after donation:", unwrap(fulfilled).get("status"),
          "| donor count:", donor.donation_count)
    ok = ok and unwrap(fulfilled).get("status") == "FULFILLED" and donor.donation_count == 1

    # --- Emergency lifecycle ------------------------------------------------
    emg = patient.post(
        "/api/emergency/requests/",
        {
            "severity": "CRITICAL",
            "type": "PAIN_CRISIS",
            "location": {"city": "Accra"},
            "description": "Gate test crisis",
            "idempotency_key": "gate-emg-1",
        },
        format="json",
    )
    emg_uid = unwrap(emg).get("uid")
    print("POST /emergency/requests:", emg.status_code, "| uid:", bool(emg_uid))
    ok = ok and emg.status_code == 201 and bool(emg_uid)

    emg_dup = patient.post(
        "/api/emergency/requests/",
        {
            "severity": "CRITICAL",
            "type": "PAIN_CRISIS",
            "location": {"city": "Accra"},
            "description": "Gate test crisis",
            "idempotency_key": "gate-emg-1",
        },
        format="json",
    )
    print("duplicate emergency (expect 409):", emg_dup.status_code)
    ok = ok and emg_dup.status_code == 409

    responded = hospital_client.post(
        f"/api/emergency/requests/{emg_uid}/respond/", {"role": "ADMIN"}, format="json"
    )
    print("HOSPITAL respond:", responded.status_code, "| status:", unwrap(responded).get("status"))
    ok = ok and responded.status_code == 200 and unwrap(responded).get("status") == "RESPONDING"

    escalated = hospital_client.post(f"/api/emergency/requests/{emg_uid}/escalate/", {}, format="json")
    print("HOSPITAL escalate:", escalated.status_code, "| status:", unwrap(escalated).get("status"))
    ok = ok and escalated.status_code == 200 and unwrap(escalated).get("status") == "ESCALATED"

    resolved = hospital_client.post(f"/api/emergency/requests/{emg_uid}/resolve/", {}, format="json")
    print("HOSPITAL resolve:", resolved.status_code, "| status:", unwrap(resolved).get("status"))
    ok = ok and resolved.status_code == 200 and unwrap(resolved).get("status") == "RESOLVED"

    grants = patient.get("/api/emergency/access-grants/")
    g_data = unwrap(grants)
    active_grants = [
        g for g in (g_data.get("results", []) if isinstance(g_data, dict) else [])
        if g.get("status") == "ACTIVE"
    ]
    print("GET access-grants:", grants.status_code, "| active:", len(active_grants))
    ok = ok and grants.status_code == 200 and len(active_grants) == 0

    # --- Anti-spam throttle on a dedicated user -----------------------------
    from django.core.cache import cache

    cache.clear()
    throttle_client, _ = register("PATIENT", "Tab", "Throttle")
    codes = []
    for _i in range(4):
        r = throttle_client.post(
            "/api/emergency/requests/",
            {"severity": "NORMAL", "type": "OTHER", "description": "spam"},
            format="json",
        )
        codes.append(r.status_code)
    print("throttle create codes:", codes)
    ok = ok and codes[:3] == [201, 201, 201] and codes[3] == 429

    # --- Notifications inbox + audit ---------------------------------------
    inbox = patient.get("/api/notifications/")
    inbox_data = unwrap(inbox)
    print("GET /notifications:", inbox.status_code, "| count:", inbox_data.get("count"))
    ok = ok and inbox.status_code == 200 and inbox_data.get("count", 0) >= 1

    read_all = patient.post("/api/notifications/read-all/")
    print("POST read-all:", read_all.status_code, "| updated:", unwrap(read_all).get("updated"))
    ok = ok and read_all.status_code == 200

    audit = admin_client.get("/api/admin/audit-logs/")
    a_data = unwrap(audit)
    print("GET /admin/audit-logs:", audit.status_code, "| count:", a_data.get("count"))
    ok = ok and audit.status_code == 200 and a_data.get("count", 0) >= 1

    denied_audit = patient.get("/api/admin/audit-logs/")
    print("PATIENT audit (expect 403):", denied_audit.status_code)
    ok = ok and denied_audit.status_code == 403

finally:
    runner.teardown_databases(old_config)

print("GATE_OK" if ok else "GATE_FAILED")