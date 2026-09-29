"""Seed approved community permissions (Stage 4.10).

Approved codes from `docs/sdlc/03-system-design/role-permission-matrix.md` §3.12:

    community.create_post  -> ALL roles (A)
    community.comment      -> ALL roles (A)
    community.report       -> ALL roles (A)
    community.moderate     -> SUPER_ADMIN/ADMIN/MODERATOR (A); everyone else D

Conditional object rules (author-only edit/delete, hide-first moderation) are
enforced in the view/service layer, not by extra seed rows.
"""

from django.db import migrations


CODES = [
    "community.create_post",
    "community.comment",
    "community.report",
    "community.moderate",
]

ALL_ROLES = [
    "SUPER_ADMIN", "ADMIN", "VERIFICATION_OFFICER", "MODERATOR", "DOCTOR",
    "HEALTHCARE_STAFF", "HOSPITAL", "PATIENT", "CAREGIVER", "BLOOD_DONOR",
    "FINANCIAL_DONOR", "ORGANIZATION",
]

ROLE_GRANTS = {
    **{role: ["community.create_post", "community.comment", "community.report"] for role in ALL_ROLES},
    "SUPER_ADMIN": ["community.create_post", "community.comment", "community.report", "community.moderate"],
    "ADMIN": ["community.create_post", "community.comment", "community.report", "community.moderate"],
    "MODERATOR": ["community.create_post", "community.comment", "community.report", "community.moderate"],
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
        ("community", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]
