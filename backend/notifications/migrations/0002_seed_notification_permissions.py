"""Seed approved notification permissions (doc role-permission-matrix §3.18).

    notifications.view         -> ALL roles (A)
    notifications.manage_prefs -> ALL roles (A)
    notifications.broadcast    -> SUP/ADM (A)
"""

from django.db import migrations


ALL_ROLES = [
    "SUPER_ADMIN", "ADMIN", "VERIFICATION_OFFICER", "MODERATOR", "DOCTOR",
    "HEALTHCARE_STAFF", "HOSPITAL", "PATIENT", "CAREGIVER", "BLOOD_DONOR",
    "FINANCIAL_DONOR", "ORGANIZATION",
]

VIEW_CODES = ["notifications.view", "notifications.manage_prefs"]


def seed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    Role = apps.get_model("accounts", "Role")
    RolePermission = apps.get_model("accounts", "RolePermission")
    codes = VIEW_CODES + ["notifications.broadcast"]
    for code in codes:
        parts = code.split(".")
        Permission.objects.get_or_create(
            code=code,
            defaults={"module": parts[0], "resource": parts[1], "action": parts[-1]},
        )
    for role_code in ALL_ROLES:
        role = Role.objects.get(code=role_code)
        for code in VIEW_CODES:
            RolePermission.objects.get_or_create(
                role=role, permission=Permission.objects.get(code=code)
            )
    for role_code in ("SUPER_ADMIN", "ADMIN"):
        role = Role.objects.get(code=role_code)
        RolePermission.objects.get_or_create(
            role=role, permission=Permission.objects.get(code="notifications.broadcast")
        )


def unseed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in VIEW_CODES + ["notifications.broadcast"]:
        RolePermission.objects.filter(permission__code=code).delete()
        Permission.objects.filter(code=code).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("notifications", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]