"""Seed approved chat permissions (Stage 4.10).

Approved codes from `docs/sdlc/03-system-design/role-permission-matrix.md` §3.17:

    chat.start -> DOCTOR/HEALTHCARE_STAFF (A); PATIENT (C13b verified-professional
                  partner — seeded and enforced at the object layer);
                  ADMIN/MODERATOR/HOSPITAL/etc. D (admin cannot read private chats)
    chat.send  -> DOCTOR/HEALTHCARE_STAFF/PATIENT (C13 participant-bound —
                  seeded and enforced by conversation membership)
"""

from django.db import migrations


CODES = ["chat.start", "chat.send"]

ROLE_GRANTS = {
    "DOCTOR": ["chat.start", "chat.send"],
    "HEALTHCARE_STAFF": ["chat.start", "chat.send"],
    "PATIENT": ["chat.start", "chat.send"],
}


def seed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    Role = apps.get_model("accounts", "Role")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in CODES:
        parts = code.split(".")
        Permission.objects.get_or_create(
            code=code, defaults={"module": parts[0], "resource": parts[1], "action": parts[-1]},
        )
    for role_code, codes in ROLE_GRANTS.items():
        role = Role.objects.get(code=role_code)
        for code in codes:
            RolePermission.objects.get_or_create(role=role, permission=Permission.objects.get(code=code))


def unseed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in CODES:
        RolePermission.objects.filter(permission__code=code).delete()
        Permission.objects.filter(code=code).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("doctors", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]
