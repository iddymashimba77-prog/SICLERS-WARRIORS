"""Seed patient-owned hydration tracker permissions.

Hydration records are personal health evidence. Only the PATIENT role receives
these codes; doctors/caregivers/admins do not get a patient hydration surface.
"""

from django.db import migrations


APPROVED_CODES = [
    ("hydration.view", None),
    ("hydration.create", None),
    ("hydration.update", None),
]

ROLE_GRANTS = {
    "PATIENT": ["hydration.view", "hydration.create", "hydration.update"],
}


def seed_hydration_permissions(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    Role = apps.get_model("accounts", "Role")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in [c for c, _ in APPROVED_CODES]:
        parts = code.split(".")
        Permission.objects.get_or_create(
            code=code,
            defaults={"module": parts[0], "resource": parts[1], "action": parts[-1]},
        )
    for role_code, codes in ROLE_GRANTS.items():
        role = Role.objects.get(code=role_code)
        for code in codes:
            RolePermission.objects.get_or_create(
                role=role, permission=Permission.objects.get(code=code)
            )


def unseed_hydration_permissions(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in [c for c, _ in APPROVED_CODES]:
        RolePermission.objects.filter(permission__code=code).delete()
        Permission.objects.filter(code=code).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0018_user_profile_photo_data"),
    ]

    operations = [
        migrations.RunPython(
            seed_hydration_permissions,
            unseed_hydration_permissions,
        ),
    ]
