"""Seed the approved AUTH-1 authorization codes (Stage 4.x).

SSoT: `docs/sdlc/03-system-design/role-permission-matrix.md`:

    doctors.view / self_manage / verify
    caregivers.invite / view / modify / remove
    consents.grant / revoke / view

Following the approved "deny by default" rule: every cell below is an ALLOW
cell from the matrix. Conditional matrix cells (C3 grantee / C4 oversight /
C6 VO) are seeded as ALLOW here and their object-level condition (owner vs
named grantee vs consent scope) is enforced in the view/services layer, per
the precedent of migrations 0004/0007.

NOTE: the earlier sibling codes `consents.manage` / `consents.verify` /
`verification.doctors.approve` / `verification.doctors.reject` (migration
0003) were never used by any gate and are left untouched — removing them from a
shared historical seed would be gratuitous churn (DENY-by-default still holds;
a role only gains what its matrix cell grants).
"""

from django.db import migrations


ROLE_GRANTS = {
    "SUPER_ADMIN": [
        "doctors.view", "doctors.verify",
        "caregivers.view",
        "consents.view",
    ],
    "ADMIN": [
        "doctors.view", "doctors.verify",
        "caregivers.view",
        "consents.view",
    ],
    "VERIFICATION_OFFICER": [
        "doctors.view", "doctors.verify",
        "consents.view",
    ],
    "MODERATOR": ["doctors.view"],
    "DOCTOR": ["doctors.view", "doctors.self_manage"],
    "HEALTHCARE_STAFF": ["doctors.view"],
    "HOSPITAL": ["doctors.view"],
    "PATIENT": [
        "doctors.view",
        "caregivers.invite", "caregivers.view", "caregivers.modify", "caregivers.remove",
        "consents.grant", "consents.revoke", "consents.view",
    ],
    "CAREGIVER": ["doctors.view", "caregivers.view", "consents.view"],
    "BLOOD_DONOR": ["doctors.view"],
    "FINANCIAL_DONOR": ["doctors.view"],
    "ORGANIZATION": ["doctors.view"],
}


def seed_auth1_permissions(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    Role = apps.get_model("accounts", "Role")
    RolePermission = apps.get_model("accounts", "RolePermission")
    codes = sorted({c for codes in ROLE_GRANTS.values() for c in codes})
    for code in codes:
        parts = code.split(".")
        Permission.objects.get_or_create(
            code=code,
            defaults={"module": parts[0], "resource": parts[1], "action": parts[-1]},
        )
    for role_code, grants in ROLE_GRANTS.items():
        role = Role.objects.get(code=role_code)
        for code in grants:
            permission = Permission.objects.get(code=code)
            RolePermission.objects.get_or_create(role=role, permission=permission)


def unseed_auth1_permissions(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    Role = apps.get_model("accounts", "Role")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in sorted({c for codes in ROLE_GRANTS.values() for c in codes}):
        RolePermission.objects.filter(permission__code=code).delete()
        Permission.objects.filter(code=code).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0010_alter_securityevent_event_type"),
    ]

    operations = [
        migrations.RunPython(seed_auth1_permissions, unseed_auth1_permissions),
    ]