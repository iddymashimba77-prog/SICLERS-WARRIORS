"""Seed the clinical-record permission codes (role-permission-matrix §3.4).

SSoT: `docs/sdlc/03-system-design/role-permission-matrix.md` §3.4:

    medical_records.view / create / update / download / upload / delete

Every cell seeded below is an **ALLOW** cell from that matrix. The conditional
cells keep their condition enforced in code, exactly like migrations 0004/0007/
0011 do, because a permission string cannot express an object-level rule:

* C2/C3 (DOC/STA/HOS/CAR `view`, `download`) — an ACTIVE, unexpired patient
  `Consent` covering `medical_records` (or a live `medical_record_links` row).
  Enforced by `medical_records.permissions.MedicalRecordAccess` +
  `medical_records.services.readable_patients`.
* C4 (SUP/ADM `view`, `download`, `delete`) — audit/oversight only: the caller
  must send `X-Oversight-Reason`, which is recorded, and the read is written to
  the append-only record history. No create/update/upload for admins (matrix D).
* C15 (DOC/STA/HOS `create`, `update`, `upload`) — clinical relationship +
  consent; the entry is attributed to the acting clinician (`recorded_by`).
* C16 (PAT) — self-entered entries only, own scope, soft delete.

Deny-by-default is preserved: a role gains only what its matrix cell grants, and
an unlisted role gains nothing.
"""

from django.db import migrations

ROLE_GRANTS = {
    "SUPER_ADMIN": [
        "medical_records.view", "medical_records.download", "medical_records.delete",
    ],
    "ADMIN": [
        "medical_records.view", "medical_records.download", "medical_records.delete",
    ],
    "DOCTOR": [
        "medical_records.view", "medical_records.create", "medical_records.update",
        "medical_records.download", "medical_records.upload",
    ],
    "HEALTHCARE_STAFF": [
        "medical_records.view", "medical_records.create", "medical_records.update",
        "medical_records.download", "medical_records.upload",
    ],
    "HOSPITAL": [
        "medical_records.view", "medical_records.create", "medical_records.update",
        "medical_records.download", "medical_records.upload",
    ],
    "PATIENT": [
        "medical_records.view", "medical_records.create", "medical_records.update",
        "medical_records.download", "medical_records.upload", "medical_records.delete",
    ],
    "CAREGIVER": ["medical_records.view", "medical_records.download"],
}


def seed_medical_record_permissions(apps, schema_editor):
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


def unseed_medical_record_permissions(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in sorted({c for codes in ROLE_GRANTS.values() for c in codes}):
        RolePermission.objects.filter(permission__code=code).delete()
        Permission.objects.filter(code=code).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0012_alter_securityevent_event_type"),
    ]

    operations = [
        migrations.RunPython(
            seed_medical_record_permissions, unseed_medical_record_permissions,
        ),
    ]