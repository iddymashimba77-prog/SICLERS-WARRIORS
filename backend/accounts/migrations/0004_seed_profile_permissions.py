"""Seed approved profile/medical-identity permissions (Stage 4.5).

Why this migration:
* The 4.5 profile surface reads/writes the `patients` 1:1 row behind the
  APPROVED permission codes from `docs/sdlc/03-system-design/
  role-permission-matrix.md` §3.3 (`patients.view`, `patients.update`,
  `patients.update_own`, `patients.manage_caregivers`) and the shared
  `auth.profile_view` (all roles).
* These codes supplement (never replace) the 4.4 seed, whose catalog used
  sibling `patients.records.*` codes. Both exist; DENY-by-default still
  holds — a role only gains what its approved matrix cell grants.

Conditional matrix cells (C2/3, C4, C7) are seeded as ALLOW here because the
object-level condition (consent/relationship/oversight) is enforced in the
view/permission layer (`accounts/permissions.py`, `patients/views.py`), not
by the seed.
"""

from django.db import migrations


APPROVED_CODES = [
    # code                     role_code(s)              (role_seed joins below)
    ("auth.profile_view", None),
    ("patients.view", None),
    ("patients.update", None),
    ("patients.update_own", None),
    ("patients.manage_caregivers", None),
]

# role -> codes granted (approved matrix §3.3 + §3.1).
ROLE_GRANTS = {
    "SUPER_ADMIN": ["auth.profile_view", "patients.view", "patients.update"],
    "ADMIN": ["auth.profile_view", "patients.view", "patients.update"],
    "VERIFICATION_OFFICER": ["auth.profile_view"],
    "MODERATOR": ["auth.profile_view"],
    "DOCTOR": ["auth.profile_view", "patients.view"],
    "HEALTHCARE_STAFF": ["auth.profile_view", "patients.view"],
    "HOSPITAL": ["auth.profile_view", "patients.view"],
    "PATIENT": [
        "auth.profile_view",
        "patients.view",
        "patients.update_own",
        "patients.manage_caregivers",
    ],
    "CAREGIVER": ["auth.profile_view", "patients.view"],
    "BLOOD_DONOR": ["auth.profile_view"],
    "FINANCIAL_DONOR": ["auth.profile_view"],
    "ORGANIZATION": ["auth.profile_view"],
}


def seed_profile_permissions(apps, schema_editor):
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
            permission = Permission.objects.get(code=code)
            RolePermission.objects.get_or_create(role=role, permission=permission)


def unseed_profile_permissions(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    Role = apps.get_model("accounts", "Role")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in [c for c, _ in APPROVED_CODES]:
        RolePermission.objects.filter(permission__code=code).delete()
        Permission.objects.filter(code=code).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0003_seed_roles_permissions"),
    ]

    operations = [
        migrations.RunPython(seed_profile_permissions, unseed_profile_permissions),
    ]