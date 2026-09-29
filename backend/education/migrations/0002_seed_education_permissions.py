"""Seed approved education permissions (Stage 4.11).

Approved codes from `docs/sdlc/03-system-design/role-permission-matrix.md` §3.16:

    education.view    -> all roles (A)
    education.publish -> SUPER_ADMIN/ADMIN (A), DOCTOR/ORGANIZATION (C12)
    education.review  -> SUPER_ADMIN/ADMIN (A)

C12 ("content requires approval/review before publication") is enforced by the
review workflow (submit -> review -> publish) in the service layer, not by extra
seed rows. DOCTOR/ORGANIZATION may create DRAFT content but it only becomes
PUBLISHED after a SUP/ADM review.
"""

from django.db import migrations

CODES = [
    "education.view",
    "education.publish",
    "education.review",
]

ALL_ROLES = [
    "SUPER_ADMIN", "ADMIN", "VERIFICATION_OFFICER", "MODERATOR", "DOCTOR",
    "HEALTHCARE_STAFF", "HOSPITAL", "PATIENT", "CAREGIVER", "BLOOD_DONOR",
    "FINANCIAL_DONOR", "ORGANIZATION",
]

ROLE_GRANTS = {
    **{role: ["education.view"] for role in ALL_ROLES},
    "SUPER_ADMIN": ["education.view", "education.publish", "education.review"],
    "ADMIN": ["education.view", "education.publish", "education.review"],
    "DOCTOR": ["education.view", "education.publish"],
    "ORGANIZATION": ["education.view", "education.publish"],
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
        ("education", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]