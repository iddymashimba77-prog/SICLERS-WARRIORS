"""Seed facility permissions (Stage 4.8).

No §3.x table exists for facilities in the approved matrix; the endpoint rows
(§6) imply the codes below (mirroring `doctors.verify` §3.14):
    facilities.verify      -> SUP/ADM/VO (A)   [POST /admin/facilities/{uid}/verify]
    facilities.self_manage -> HOSPITAL (A)     [GET/PATCH /facilities/me]
"""

from django.db import migrations


CODES = ["facilities.verify", "facilities.self_manage"]


def seed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    Role = apps.get_model("accounts", "Role")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in CODES:
        parts = code.split(".")
        Permission.objects.get_or_create(
            code=code,
            defaults={"module": parts[0], "resource": parts[1], "action": parts[-1]},
        )
    for role_code, codes in {
        "SUPER_ADMIN": ["facilities.verify"],
        "ADMIN": ["facilities.verify"],
        "VERIFICATION_OFFICER": ["facilities.verify"],
        "HOSPITAL": ["facilities.self_manage"],
    }.items():
        role = Role.objects.get(code=role_code)
        for code in codes:
            RolePermission.objects.get_or_create(
                role=role, permission=Permission.objects.get(code=code)
            )


def unseed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in CODES:
        RolePermission.objects.filter(permission__code=code).delete()
        Permission.objects.filter(code=code).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("facilities", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]