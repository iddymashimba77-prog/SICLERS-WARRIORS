"""Seed approved blood-network permissions (Stage 4.8).

Approved codes from `docs/sdlc/03-system-design/role-permission-matrix.md` §3.8:

    blood_donors.self_manage   -> BLOOD_DONOR (A)
    blood_donors.view          -> SUP/ADM (A), STA (A); VO/HOS conditional (C6/C7) NOT seeded
    blood_requests.create      -> SUP/ADM (A), PATIENT (A); DOC/HOS/STA (C15/C7), CAR (C14) NOT seeded
    blood_requests.view        -> SUP/ADM (A), PATIENT (A, own scope); BLD (C8, eligible);
                                  VO/DOC/HOS/STA/CAR conditional NOT seeded
    blood_requests.verify      -> SUP/ADM/VO (A)
    blood_requests.respond     -> BLOOD_DONOR (A, own match)
    blood_matches.view         -> SUP/ADM (A); PATIENT/BLD (C9 own) seeded + own-scope enforced
    blood_matches.run          -> SUP/ADM/VO (A)

C8 (eligible donors only) and C9 (own scope) are *object-level* rules enforced
in blood_network views on top of the grant (a grant is never a blanket
backdoor — role-permission-design §21).
"""

from django.db import migrations


CODES = [
    "blood_donors.self_manage",
    "blood_donors.view",
    "blood_requests.create",
    "blood_requests.view",
    "blood_requests.verify",
    "blood_requests.respond",
    "blood_matches.view",
    "blood_matches.run",
]

ROLE_GRANTS = {
    "SUPER_ADMIN": CODES,
    "ADMIN": [
        "blood_donors.view",
        "blood_requests.create",
        "blood_requests.view",
        "blood_requests.verify",
        "blood_matches.view",
        "blood_matches.run",
    ],
    "VERIFICATION_OFFICER": [
        "blood_requests.verify",
        "blood_matches.run",
    ],
    "HEALTHCARE_STAFF": ["blood_donors.view"],
    "PATIENT": [
        "blood_requests.create",
        "blood_requests.view",
        "blood_matches.view",
    ],
    "BLOOD_DONOR": [
        "blood_donors.self_manage",
        "blood_requests.view",
        "blood_requests.respond",
        "blood_matches.view",
    ],
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
        ("blood_network", "0002_bloodrequest_idempotency_key"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]