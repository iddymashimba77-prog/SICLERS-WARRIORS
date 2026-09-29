"""Seed approved analytics/reporting permissions (Stage 4.14).

Approved codes from `docs/sdlc/03-system-design/role-permission-matrix.md`
§3.19:

    analytics.view            SUPER_ADMIN/ADMIN (A), VERIFICATION_OFFICER (C6)
    analytics.health_trends   SUPER_ADMIN (C4) / ADMIN (C4) / PATIENT (A)
    analytics.export          SUPER_ADMIN (A), ADMIN (C4)

C6 / C4 are workflow gates, NOT extra grants — a VERIFICATION_OFFICER with
``analytics.view`` is limited to the verification metric set in the service
layer (``AnalyticsService.allowed_metrics``); an ADMIN export requires a C4
``reason`` in the request. ``analytics.health_trends`` is seeded for PATIENT
too (ODD-8 default), but has NO endpoint in this stage: `/ai/trends/{uid}` is
a future placeholder (AD-2) and DOCTOR/CAREGIVER grants (C2/C3) wait for the
consent stage — both documented in the 4.14 note as NOT IMPLEMENTED.
"""

from django.db import migrations

CODES = [
    "analytics.view",
    "analytics.health_trends",
    "analytics.export",
]

ROLE_GRANTS = {
    "SUPER_ADMIN": ["analytics.view", "analytics.health_trends", "analytics.export"],
    "ADMIN": ["analytics.view", "analytics.health_trends", "analytics.export"],
    "VERIFICATION_OFFICER": ["analytics.view"],
    "PATIENT": ["analytics.health_trends"],
}


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
    for role_code, codes in ROLE_GRANTS.items():
        role = Role.objects.get(code=role_code)
        for code in codes:
            RolePermission.objects.get_or_create(
                role=role, permission=Permission.objects.get(code=code),
            )


def unseed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in CODES:
        RolePermission.objects.filter(permission__code=code).delete()
        Permission.objects.filter(code=code).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("analytics", "0001_initial"),
        ("accounts", "0003_seed_roles_permissions"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]