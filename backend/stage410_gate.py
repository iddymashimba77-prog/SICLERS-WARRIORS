"""Stage 4.10 community & communication gate — ephemeral SQLite ONLY.

Purpose
-------
Proves the Stage 4.10 community + private-chat additions end to end on top of
the Stage 4.9 surface (`stage49_gate.py`):

  1. register PATIENT/PATIENT2; create DOCTOR/MODERATOR/ADMIN via ORM.
  2. community post create -> 201, HTML sanitized (no <script>).
  3. comment + reaction toggle.
  4. report create -> 201; duplicate report -> 400.
  5. moderator resolves a report hide-first -> post HIDDEN; non-moderator
     admin-reports access -> 403.
  6. chat start: patient<->doctor -> 201; patient<->patient -> 403 (C13b).
  7. message send -> 201; unread -> 1; read -> 0.
  8. isolation: non-participant retrieve -> 404; ADMIN conversation list empty.
  9. message delete tombstone masks the body.
 10. audit rows recorded for community + chat mutations.

Run:  venv/bin/python stage410_gate.py   (from backend/)
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

    patient, preg = register("PATIENT", "Paul", "Patient")
    other, oreg = register("PATIENT", "Olive", "Other")
    doctor_client, doctor = orm_user("DOCTOR")
    moderator_client, _ = orm_user("MODERATOR")
    admin_client, _ = orm_user("ADMIN")
    ok = preg.status_code == 201 and oreg.status_code == 201
    print("register patients:", preg.status_code, oreg.status_code)

    # --- Community post ------------------------------------------------------
    created = patient.post(
        "/api/community/posts/",
        {"title": "Hello", "content": '<script>x</script>Support <b>group</b>', "category": "SUPPORT"},
        format="json",
    )
    body = unwrap(created)
    post_uid = body.get("uid")
    clean = "<script" not in (body.get("content") or "")
    print("POST /community/posts:", created.status_code, "| sanitized:", clean)
    ok = ok and created.status_code == 201 and bool(post_uid) and clean

    comment = other.post(
        f"/api/community/posts/{post_uid}/comments/", {"content": "Stay strong"}, format="json",
    )
    print("POST comment:", comment.status_code)
    ok = ok and comment.status_code == 201

    react = other.post(
        f"/api/community/posts/{post_uid}/reactions/", {"reaction_type": "LIKE"}, format="json",
    )
    print("POST reaction:", react.status_code, "| reacted:", unwrap(react).get("reacted"))
    ok = ok and react.status_code == 200 and unwrap(react).get("reacted") is True

    # --- Reports + hide-first moderation ------------------------------------
    from community.models import CommunityPost

    post_pk = CommunityPost.objects.get(uid=post_uid).pk
    report = other.post(
        "/api/community/reports/",
        {"target_type": "POST", "target_id": post_pk, "reason": "spam"},
        format="json",
    )
    dup = other.post(
        "/api/community/reports/",
        {"target_type": "POST", "target_id": post_pk, "reason": "again"},
        format="json",
    )
    print("POST report:", report.status_code, "| duplicate (expect 400):", dup.status_code)
    ok = ok and report.status_code == 201 and dup.status_code == 400

    report_id = unwrap(report).get("id")
    denied = doctor_client.get("/api/admin/community/reports/")
    listing = moderator_client.get("/api/admin/community/reports/")
    print("admin reports non-mod (expect 403):", denied.status_code, "| mod:", listing.status_code)
    ok = ok and denied.status_code == 403 and listing.status_code == 200

    resolved = moderator_client.post(
        f"/api/admin/community/reports/{report_id}/resolve/",
        {"status": "RESOLVED", "action": "HIDE", "review_notes": "policy breach"},
        format="json",
    )
    hidden = other.get(f"/api/community/posts/{post_uid}/")
    print("resolve HIDE:", resolved.status_code, "| hidden from others (expect 404):", hidden.status_code)
    ok = ok and resolved.status_code == 200 and hidden.status_code == 404

    # --- Chat start (C13b) ---------------------------------------------------
    good = patient.post(
        "/api/chat/conversations/", {"participant_uid": str(doctor.uid)}, format="json",
    )
    bad = patient.post(
        "/api/chat/conversations/",
        {"participant_uid": str(oreg.data["user"]["uid"])},
        format="json",
    )
    conv_uid = unwrap(good).get("uid")
    print("chat patient<->doctor:", good.status_code, "| patient<->patient (expect 403):", bad.status_code)
    ok = ok and good.status_code == 201 and bool(conv_uid) and bad.status_code == 403

    # --- Messages / unread ---------------------------------------------------
    sent = doctor_client.post(
        f"/api/chat/conversations/{conv_uid}/messages/",
        {"content": '<script>x</script>Hello <b>there</b>'},
        format="json",
    )
    msg = unwrap(sent)
    clean_msg = "<script" not in (msg.get("content") or "")
    listing = patient.get("/api/chat/conversations/")
    unread = listing.data["results"][0]["unread_count"]
    read = patient.post(f"/api/chat/conversations/{conv_uid}/read/")
    after = patient.get("/api/chat/conversations/")
    unread_after = after.data["results"][0]["unread_count"]
    print(
        "send:", sent.status_code, "| sanitized:", clean_msg,
        "| unread:", unread, "-> ", unread_after,
    )
    ok = ok and sent.status_code == 201 and clean_msg and unread == 1 and read.status_code == 200 and unread_after == 0

    # --- Isolation -----------------------------------------------------------
    foreign = other.get(f"/api/chat/conversations/{conv_uid}/")
    admin_list = admin_client.get("/api/chat/conversations/")
    print("non-participant (expect 404):", foreign.status_code, "| ADMIN list count:", admin_list.data["count"])
    ok = ok and foreign.status_code == 404 and admin_list.data["count"] == 0

    # --- Tombstone -----------------------------------------------------------
    deleted = doctor_client.delete(
        f"/api/chat/conversations/{conv_uid}/messages/{msg['uid']}/"
    )
    masked = patient.get(f"/api/chat/conversations/{conv_uid}/messages/")
    first = masked.data["results"][0]
    print("delete message:", deleted.status_code, "| masked:", first["deleted"] and first["content"] == "")
    ok = ok and deleted.status_code == 204 and first["deleted"] and first["content"] == ""

    # --- Audit ---------------------------------------------------------------
    codes = {"community_posts.create", "messages.send", "community.moderate"}
    found = set(AuditLog.objects.filter(action_code__in=codes).values_list("action_code", flat=True))
    print("audit codes present:", sorted(found))
    ok = ok and codes.issubset(found)

finally:
    runner.teardown_databases(old_config)

print("GATE_OK" if ok else "GATE_FAILED")
