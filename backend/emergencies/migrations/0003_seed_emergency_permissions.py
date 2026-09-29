"""Seed approved emergency permissions (Stage 4.8).

Approved codes from `docs/sdlc/03-system-design/role-permission-matrix.md` §3.9:

    emergency_requests.create    -> SUP/ADM/DOC/STA/HOS/PATIENT (A); CAR (C14) NOT seeded
    emergency_requests.view      -> SUP/ADM/DOC/STA/HOS/PATIENT/CAREGIVER (A)
    emergency_requests.manage    -> SUP/ADM/HOSPITAL (A); DOC/STA/PAT/CAR (C, part-of) NOT seeded
    emergency_requests.resolve   -> SUP/ADM/HOSPITAL (A); DOC/STA/PAT/CAR (C) NOT seeded
    emergency_requests.override_access -> SUP (A); everyone else (C10) NOT seeded

Conditional cells (C) for manage/resolve are scoped to requests the actor is a
part of; such actors are not pre-supplying the code until the responder-on-
boarding stage. There is NO emergency=BYPASS-ALL rule (§16).
"""

from django.db import migrations


CODES = [
    "emergency_requests.create",
    "emergency_requests.view",
    "emergency_requests.manage",
    "emergency_requests.resolve",
    "emergency_requests.override_access",
]

ROLE_GRANTS = {
    "SUPER_ADMIN": CODES,
    "ADMIN": [
        "emergency_requests.create",
        "emergency_requests.view",
        "emergency_requests.manage",
        "emergency_requests.resolve",
    ],
    "DOCTOR": ["emergency_requests.create", "emergency_requests.view"],
    "HEALTHCARE_STAFF": ["emergency_requests.create", "emergency_requests.view"],
    "HOSPITAL": [
        "emergency_requests.create",
        "emergency_requests.view",
        "emergency_requests.manage",
        "emergency_requests.resolve",
    ],
    "PATIENT": ["emergency_requests.create", "emergency_requests.view"],
    "CAREGIVER": ["emergency_requests.view"],
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
            permission = Permission.objects.get(code=code)
            RolePermission.objects.get_or_create(role=role, permission=permission)


def unseed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in CODES:
        RolePermission.objects.filter(permission__code=code).delete()
        Permission.objects.filter(code=code).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("emergencies", "0002_emergencyrequest_idempotency_key"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]