"""Seed approved audit permissions (doc role-permission-matrix §3.20).

    audit_logs.view   -> SUP/ADM (A); VO (C6, verification workflow) NOT seeded
    audit_logs.export -> SUP (A); ADM (C4) NOT seeded
"""

from django.db import migrations


CODES = ["audit_logs.view", "audit_logs.export"]


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
        "SUPER_ADMIN": CODES,
        "ADMIN": ["audit_logs.view"],
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
        ("audit", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]