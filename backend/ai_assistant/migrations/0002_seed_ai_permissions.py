"""Seed approved AI assistant permission (Stage 4.15).

Approved code from `docs/sdlc/03-system-design/role-permission-matrix.md`
§3.21:

    ai.use   A (ALL roles)

All twelve roles may *use* the assistant (chat). The permission ONLY opens
the chat endpoint; the safety layer (BR-010/011, FR-AI-006) and the privacy
layer (own data only, minimum necessary) enforce the real boundaries. The
trends endpoint additionally requires ``analytics.health_trends`` (seeded in
stage 4.14) and remains owner-only until the consent surface lands.

This migration intentionally mirrors the accounts/analytics seed pattern
(``RunPython`` + reverse unseed) so role grants stay revisable.
"""

from django.db import migrations

CODE = "ai.use"
ALL_ROLE_CODES = [
    "SUPER_ADMIN",
    "ADMIN",
    "VERIFICATION_OFFICER",
    "MODERATOR",
    "DOCTOR",
    "HEALTHCARE_STAFF",
    "HOSPITAL",
    "PATIENT",
    "CAREGIVER",
    "BLOOD_DONOR",
    "FINANCIAL_DONOR",
    "ORGANIZATION",
]


def seed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    Role = apps.get_model("accounts", "Role")
    RolePermission = apps.get_model("accounts", "RolePermission")
    permission, _ = Permission.objects.get_or_create(
        code=CODE,
        defaults={"module": "ai", "resource": "use", "action": "use"},
    )
    roles = Role.objects.filter(code__in=ALL_ROLE_CODES)
    for role in roles:
        RolePermission.objects.get_or_create(role=role, permission=permission)


def unseed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    role_codes = [
        code
        for code in ALL_ROLE_CODES
        if Permission.objects.filter(code=CODE).exists()
    ]
    permission = Permission.objects.get(code=CODE)
    RolePermission.objects.filter(
        role__code__in=role_codes, permission=permission
    ).delete()
    Permission.objects.filter(code=CODE).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("ai_assistant", "0001_initial"),
        ("accounts", "0003_seed_roles_permissions"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]