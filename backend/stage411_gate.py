"""Stage 4.11 education gate — ephemeral SQLite ONLY.

Purpose
-------
Proves the Stage 4.11 education additions end to end on top of the Stage 4.10
surface (`stage410_gate.py`):

  1. register PATIENT; create DOCTOR/SUPER_ADMIN via ORM.
  2. public categories + published-only feed (draft locked from non-author).
  3. doctor creates DRAFT (education.publish, C12) -> sanitized.
  4. author submits -> IN_REVIEW; non-author submit denied.
  5. patient/other publish attempts denied; super-admin approves -> PUBLISHED;
     a second publish of a non-pending piece is rejected.
  6. admin review list shows only pending queue for reviewer; non-review 403.
  7. search + category filter return only published matches.
  8. audit rows recorded for create/submit/review.
  9. write throttle -> 429 after 30 rapid creates.

Run:  venv/bin/python stage411_gate.py   (from backend/)
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
    from education.models import EducationCategory

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

    def orm_user(role_code, account_status="ACTIVE"):
        user = User.objects.create_user(
            email=f"{role_code.lower()}-{uuid.uuid4().hex[:10]}@example.com",
            password="Str0ng!Pass9",
            first_name="Gate",
            last_name=role_code.title(),
            account_status=account_status,
        )
        UserRole.objects.create(user=user, role=Role.objects.get(code=role_code))
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {RefreshToken.for_user(user).access_token}")
        return client, user

    patient, preg = register("PATIENT", "Pat", "Patient")
    anon = APIClient()
    doctor_client, doctor = orm_user("DOCTOR")
    admin_client, _ = orm_user("SUPER_ADMIN")
    ok = preg.status_code == 201
    print("register patient (API):", preg.status_code)

    # --- Public read surface -------------------------------------------------
    cats = unwrap(anon.get("/api/education/categories/"))
    cat_codes = [c["code"] for c in cats.get("results", [])]
    print(
        "categories public:", anon.get("/api/education/categories/").status_code,
        "| seeded:", EducationCategory.objects.count(), "| codes:", ",".join(cat_codes),
    )
    ok = ok and EducationCategory.objects.count() == 6

    # --- Authoring (doctor, education.publish) -------------------------------
    draft = doctor_client.post(
        "/api/education/content/",
        {"title": "Crisis basics", "body": '<script>x</script>Learn <b>sickling</b> risks', "category": "CRISIS_PREVENTION"},
        format="json",
    )
    d = unwrap(draft)
    is_draft = d.get("status") == "DRAFT"
    clean = "<script" not in (d.get("body") or "")
    print("POST /education/content:", draft.status_code, "| status:", d.get("status"), "| sanitized:", clean)
    ok = ok and draft.status_code == 201 and is_draft and clean
    content_uid = d.get("uid")

    # Draft locked from non-author (member should get 404) and public feed.
    hidden = patient.get(f"/api/education/content/{content_uid}/")
    feed = unwrap(anon.get("/api/education/content/"))
    print(
        "draft locked from member (expect 404):", hidden.status_code,
        "| public feed count:", feed.get("count"),
    )
    ok = ok and hidden.status_code == 404 and feed.get("count") == 0

    # Non-author cannot patch.
    hijack = patient.patch(
        f"/api/education/content/{content_uid}/", {"body": "hijack"}, format="json",
    )
    print("non-author patch (expect 403):", hijack.status_code)
    ok = ok and hijack.status_code == 403

    # PATIENT cannot publish at all (no education.publish).
    denied = patient.post(
        "/api/education/content/",
        {"title": "x", "body": "y", "category": "LIVING_WELL"},
        format="json",
    )
    print("patient create (expect 403):", denied.status_code)
    ok = ok and denied.status_code == 403

    # --- Submit + review workflow (C12) --------------------------------------
    submitted = doctor_client.post(f"/api/education/content/{content_uid}/submit/")
    non_author_submit = patient.post(f"/api/education/content/{content_uid}/submit/")
    print(
        "submit:", submitted.status_code, "->", unwrap(submitted).get("status"),
        "| non-author submit (expect 403):", non_author_submit.status_code,
    )
    ok = ok and submitted.status_code == 200 and unwrap(submitted).get("status") == "IN_REVIEW" \
        and non_author_submit.status_code == 403

    # Review list: non-reviewer denied; reviewer sees the pending item.
    denied_admin = patient.get("/api/admin/education/content/")
    queue = unwrap(admin_client.get("/api/admin/education/content/?status=IN_REVIEW"))
    print(
        "admin list non-review (expect 403):", denied_admin.status_code,
        "| pending count:", queue.get("count"),
    )
    ok = ok and denied_admin.status_code == 403 and queue.get("count") == 1

    approved = admin_client.post(
        f"/api/admin/education/content/{content_uid}/review/",
        {"decision": "approve"},
        format="json",
    )
    print("review approve:", approved.status_code, "->", unwrap(approved).get("status"))
    ok = ok and approved.status_code == 200 and unwrap(approved).get("status") == "PUBLISHED"

    # After publish it is visible to the public feed, search and category filter.
    feed = unwrap(anon.get("/api/education/content/"))
    search = unwrap(anon.get("/api/education/content/?q=crisis"))
    cat = unwrap(anon.get("/api/education/content/?category=CRISIS_PREVENTION"))
    print(
        "published visible:", feed.get("count"),
        "| search:", search.get("count"), "| category:", cat.get("count"),
    )
    ok = ok and feed.get("count") == 1 and search.get("count") == 1 and cat.get("count") == 1

    # Re-approving a published piece is invalid.
    repeat = admin_client.post(
        f"/api/admin/education/content/{content_uid}/review/",
        {"decision": "approve"},
        format="json",
    )
    print("re-review published (expect 400):", repeat.status_code)
    ok = ok and repeat.status_code == 400

    # --- Data boundary -------------------------------------------------------
    public = anon.get(f"/api/education/content/{content_uid}/")
    author = unwrap(public).get("author") or {}
    priv_leak = set(author.keys()) - {"uid", "display_name"}
    print("author projection keys:", sorted(author.keys()))
    ok = ok and not priv_leak and "rejection_reason" not in unwrap(public)

    # --- Throttle ------------------------------------------------------------
    for i in range(30):
        doctor_client.post(
            "/api/education/content/",
            {"title": f"d{i}", "body": "b", "category": "LIVING_WELL"},
            format="json",
        )
    blocked = doctor_client.post(
        "/api/education/content/",
        {"title": "x", "body": "y", "category": "LIVING_WELL"},
        format="json",
    )
    print("write throttle (expect 429):", blocked.status_code)
    ok = ok and blocked.status_code == 429

    # --- Audit ---------------------------------------------------------------
    codes = {"education.content.create", "education.content.submit", "education.content.review"}
    found = set(AuditLog.objects.filter(action_code__in=codes).values_list("action_code", flat=True))
    print("audit codes present:", sorted(found))
    ok = ok and codes.issubset(found)

finally:
    runner.teardown_databases(old_config)

print("GATE_OK" if ok else "GATE_FAILED")