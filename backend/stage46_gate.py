"""Stage 4.6 medication & health-tracking gate — ephemeral SQLite ONLY.

Purpose
-------
Proves the server-side medication/health-tracking surface (approved Stage 4.6):

  1. register PATIENT + self-register CAREGIVER (control subject).
  2. GET/POST /api/medications/ (create/list own) + invalid route -> 400.
  3. GET/POST /api/medications/{uid}/schedule/ + bad days_of_week -> 400.
  4. POST /api/medications/{uid}/log-dose/ TAKEN (+ header idempotency) -> 201,
     duplicate key -> 409 IDEMPOTENCY_CONFLICT; MISSED without taken_at.
  5. GET /api/medications/{uid}/events/ -> paginated history.
  6. GET /api/medications/stats/ -> derived adherence (not stored).
  7. GET/POST /api/symptoms/ + GET /api/symptom-types/ (is_pain_related).
  8. GET /api/health-timeline/ -> materialized MED_STARTED/DOSE_*/SYMPTOM.
  9. GET /api/patients/me/dashboard/ -> approved FR-MED-007 aggregate.
 10. Security: ownership (user B -> 404 on A's med), CAREGIVER -> 403,
      DELETE = soft delete 204 + list empty; audit events recorded (type only).

Runs against ephemeral SQLite (config/settings/ephemeral_test.py) exactly like
stage45_gate.py. Never contacts Postgres; no superuser / DROP-CREATE.

Run:  venv/bin/python stage46_gate.py   (from backend/)
Expected final line:  GATE_OK
"""

import datetime
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

    def unwrap(resp):
        """Deal with both pre-render (envelope-free .data) and any wrapped payload."""
        d = resp.data or {}
        if isinstance(d, dict) and "data" in d:
            return d["data"]
        return d

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
    access = (s1.data or {}).get("access")
    ok = ok and bool(access)
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

    # --- Medications CRUD ---------------------------------------------------
    m1 = c.post(
        "/api/medications/",
        {
            "name": "Hydroxyurea",
            "generic_name": "hydroxycarbamide",
            "strength": "500 mg",
            "dosage": "1 tablet",
            "route": "ORAL",
            "frequency": "daily",
            "start_date": "2026-01-01",
            "end_date": "2026-12-31",
        },
        format="json",
    )
    print("POST /medications:", m1.status_code)
    md = unwrap(m1)
    med_uid = md.get("uid")
    ok = ok and m1.status_code == 201 and bool(med_uid)

    bad = c.post(
        "/api/medications/",
        {"name": "Bad", "route": "SPACE", "frequency": "x",
         "start_date": "2026-01-01"},
        format="json",
    )
    print("POST bad route (expect 400):", bad.status_code)
    ok = ok and bad.status_code == 400

    date_bad = c.post(
        "/api/medications/",
        {"name": "Reverse", "route": "ORAL", "frequency": "x",
         "start_date": "2026-12-31", "end_date": "2026-01-01"},
        format="json",
    )
    print("POST end<start (expect 400):", date_bad.status_code)
    ok = ok and date_bad.status_code == 400

    ml = c.get("/api/medications/")
    ml_data = unwrap(ml)
    rows = ml_data.get("results", []) if isinstance(ml_data, dict) else []
    print("GET /medications:", ml.status_code, "| count:", ml_data.get("count"))
    ok = ok and ml.status_code == 200 and rows and rows[0]["uid"] == med_uid

    # --- Schedules ----------------------------------------------------------
    sc1 = c.post(
        f"/api/medications/{med_uid}/schedule/",
        {"time_of_day": "08:00:00", "days_of_week": ["MON", "WED", "FRI"]},
        format="json",
    )
    print("POST schedule:", sc1.status_code)
    sched_uid = unwrap(sc1).get("uid")
    ok = ok and sc1.status_code == 201 and bool(sched_uid)

    sc_bad = c.post(
        f"/api/medications/{med_uid}/schedule/",
        {"time_of_day": "08:00:00", "days_of_week": ["MONDAY"]},
        format="json",
    )
    print("POST bad day (expect 400):", sc_bad.status_code)
    ok = ok and sc_bad.status_code == 400

    # --- Dose logging (idempotent, status-aware) ----------------------------
    key = f"k-{uuid.uuid4().hex}"
    d1 = c.post(
        f"/api/medications/{med_uid}/log-dose/",
        {"schedule": sched_uid, "status": "TAKEN",
         "taken_at": "2026-09-16T08:05:00Z"},
        HTTP_IDEMPOTENCY_KEY=key,
        format="json",
    )
    print("POST log-dose TAKEN:", d1.status_code)
    ok = ok and d1.status_code == 201

    d2 = c.post(
        f"/api/medications/{med_uid}/log-dose/",
        {"schedule": sched_uid, "status": "TAKEN",
         "taken_at": "2026-09-16T08:05:00Z"},
        HTTP_IDEMPOTENCY_KEY=key,
        format="json",
    )
    print("duplicate idempotency (expect 409):", d2.status_code)
    ok = ok and d2.status_code == 409

    d3 = c.post(
        f"/api/medications/{med_uid}/log-dose/",
        {"schedule": sched_uid, "status": "MISSED",
         "idempotency_key": f"k-{uuid.uuid4().hex}"},
        format="json",
    )
    print("POST log-dose MISSED:", d3.status_code)
    ok = ok and d3.status_code == 201

    d4 = c.post(
        f"/api/medications/{med_uid}/log-dose/",
        {"schedule": sched_uid, "status": "TAKEN"},
        format="json",
    )
    print("TAKEN without taken_at (expect 400):", d4.status_code)
    ok = ok and d4.status_code == 400

    ev = c.get(f"/api/medications/{med_uid}/events/")
    ev_data = unwrap(ev)
    print("GET events:", ev.status_code, "| count:", ev_data.get("count"))
    ok = ok and ev.status_code == 200 and ev_data.get("count", 0) >= 2

    st = c.get("/api/medications/stats/")
    st_data = unwrap(st)
    overall = st_data.get("overall") or {}
    print("GET stats:", st.status_code, "| expected:", overall.get("expected"),
          "| taken:", overall.get("taken"), "| pct:", overall.get("adherence_pct"))
    ok = ok and st.status_code == 200 and overall.get("taken", 0) >= 1 \
        and overall.get("expected", 0) >= 1

    # --- Symptoms + vocabulary ---------------------------------------------
    rec_at = (datetime.datetime.now(datetime.timezone.utc)
              - datetime.timedelta(hours=2)).isoformat().replace("+00:00", "Z")
    sym = c.post(
        "/api/symptoms/",
        {"symptom_type_code": "pain_crisis", "pain_level": 7,
         "triggers": ["cold"], "duration_minutes": 180,
         "recorded_at": rec_at},
        format="json",
    )
    print("POST /symptoms:", sym.status_code)
    ok = ok and sym.status_code == 201

    sym_bad = c.post(
        "/api/symptoms/",
        {"pain_level": 11, "recorded_at": "2026-09-16T10:00:00Z"},
        format="json",
    )
    print("POST pain=11 (expect 400):", sym_bad.status_code)
    ok = ok and sym_bad.status_code == 400

    sym_list = c.get("/api/symptoms/")
    print("GET /symptoms:", sym_list.status_code)
    ok = ok and sym_list.status_code == 200

    types = c.get("/api/symptom-types/")
    t_data = unwrap(types)
    t_rows = t_data.get("results", []) if isinstance(t_data, dict) else t_data
    pain_rows = [t for t in t_rows if t.get("is_pain_related")]
    print("GET /symptom-types:", types.status_code, "| total:", len(t_rows),
          "| pain:", len(pain_rows))
    ok = ok and types.status_code == 200 and len(pain_rows) >= 1

    # --- Health timeline + dashboard ----------------------------------------
    tl = c.get("/api/health-timeline/")
    tl_data = unwrap(tl)
    tl_types = {r.get("event_type") for r in tl_data.get("results", [])}
    print("GET /health-timeline:", tl.status_code, "| types:", sorted(tl_types))
    ok = ok and tl.status_code == 200 \
        and {"MED_STARTED", "DOSE_TAKEN", "SYMPTOM_RECORDED"} <= tl_types

    dash = c.get("/api/patients/me/dashboard/")
    dash_data = unwrap(dash)
    print("GET dashboard:", dash.status_code,
          "| active meds:", (dash_data.get("medications") or {}).get("active_count"))
    ok = ok and dash.status_code == 200 \
        and (dash_data.get("medications") or {}).get("active_count") == 1

    # --- Security: ownership, role-deny, soft-delete, audit ------------------
    c2 = APIClient()
    cg = c2.post(
        "/api/auth/register/",
        {"email": f"c-{uuid.uuid4().hex[:10]}@example.com",
         "password": "Str0ng!Pass9", "first_name": "Craig",
         "last_name": "Caregiver", "role_code": "CAREGIVER"},
        format="json",
    )
    cg_access = (cg.data or {}).get("access")
    c2.credentials(HTTP_AUTHORIZATION=f"Bearer {cg_access}")
    other = c2.get(f"/api/medications/{med_uid}/")
    print("CAREGIVER GET med (expect 403):", other.status_code)
    ok = ok and other.status_code == 403

    c3 = APIClient()
    p2 = c3.post(
        "/api/auth/register/",
        {"email": f"q-{uuid.uuid4().hex[:10]}@example.com",
         "password": "Str0ng!Pass9", "first_name": "Quinn",
         "last_name": "Quiet", "role_code": "PATIENT"},
        format="json",
    )
    c3.credentials(HTTP_AUTHORIZATION=f"Bearer {(p2.data or {}).get('access')}")
    stolen = c3.get(f"/api/medications/{med_uid}/")
    print("other patient GET (expect 404):", stolen.status_code)
    ok = ok and stolen.status_code == 404

    dele = c.delete(f"/api/medications/{med_uid}/")
    print("DELETE (soft, expect 204):", dele.status_code)
    ok = ok and dele.status_code == 204

    after = c.get("/api/medications/")
    after_data = unwrap(after)
    print("GET after delete: count:", after_data.get("count"))
    ok = ok and after_data.get("count", 1) == 0

    from accounts.models import SecurityEvent, User
    user = User.objects.get(email=email)
    kinds = set(SecurityEvent.objects.filter(user=user).values_list("event_type", flat=True))
    print("audit events:", sorted(kinds))
    ok = ok and {"MEDICATION_CREATED", "DOSE_LOGGED", "SYMPTOM_RECORDED"} <= kinds

finally:
    runner.teardown_databases(old_config)

print("GATE_OK" if ok else "GATE_FAILED")