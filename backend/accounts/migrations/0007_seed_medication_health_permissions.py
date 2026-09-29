"""Seed approved medication/health-tracking permissions (Stage 4.6).

Approved codes from `docs/sdlc/03-system-design/role-permission-matrix.md`
(§3.3 medication & symptom surface):

    medications.create / view / update / delete   -> PATIENT (own scope)
    symptoms.create / view                        -> PATIENT (own scope)
    symptoms.analyze                              -> analytic/consent-gated
                                                    surface (NOT seeded to any
                                                    role yet — deny by default
                                                    until the analytics stage)

Following the approved "deny by default" rule (§18/§19), conditional matrix
cells (DOCTOR/CAREGIVER/HOSPITAL C2/C3, C4 oversight) are deliberately NOT
granted here: cross-patient medical access flows through the relationship+
consent architecture implemented in the consent stage, later. Granting those
codes now would open medico-legal access before the consent gates exist.

Existing (Stage 4.4) sibling codes such as `medications.prescribe` /
`symptoms.record` remain untouched — the approved codes live alongside them;
deny-by-default still holds (a role only gains what its matrix cell grants).
"""

from django.db import migrations


APPROVED_CODES = [
    ("medications.create", None),
    ("medications.view", None),
    ("medications.update", None),
    ("medications.delete", None),
    ("symptoms.create", None),
    ("symptoms.view", None),
    ("symptoms.analyze", None),
]

# role -> codes granted (approved matrix §3.3). PATIENT only, own scope.
ROLE_GRANTS = {
    "PATIENT": [
        "medications.create",
        "medications.view",
        "medications.update",
        "medications.delete",
        "symptoms.create",
        "symptoms.view",
    ],
}


def seed_medication_health_permissions(apps, schema_editor):
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


def unseed_medication_health_permissions(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in [c for c, _ in APPROVED_CODES]:
        RolePermission.objects.filter(permission__code=code).delete()
        Permission.objects.filter(code=code).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0006_alter_securityevent_event_type"),
    ]

    operations = [
        migrations.RunPython(
            seed_medication_health_permissions,
            unseed_medication_health_permissions,
        ),
    ]