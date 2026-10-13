"""Seed appointment permissions (§11).

New capability codes, kept in the existing ``module.resource.action`` scheme:

    appointments.read      -> roles allowed to *see* appointment rows
    appointments.write_own  -> book/cancel for oneself or a consented patient
    appointments.manage     -> directory oversight (all rows, clinical notes)

PATIENT/CAREGIVER act on their own relationship, so they hold the `own` codes;
clinical staff read rows they are attached to; ADMIN/SUPER_ADMIN hold `manage`.
SUPER_ADMIN does not receive read/write_own — oversight for them is `manage`
only, so the clinical surface is not opened implicitly.
"""

from django.db import migrations

CODES = [
    "appointments.read",
    "appointments.write_own",
    "appointments.manage",
]

ROLE_GRANTS = {
    "PATIENT": ["appointments.read", "appointments.write_own"],
    "CAREGIVER": ["appointments.read", "appointments.write_own"],
    "DOCTOR": ["appointments.read", "appointments.write_own"],
    "HEALTHCARE_STAFF": ["appointments.read"],
    "HOSPITAL": ["appointments.read"],
    "ADMIN": ["appointments.read", "appointments.manage"],
    "SUPER_ADMIN": ["appointments.read", "appointments.manage"],
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
        role = Role.objects.filter(code=role_code).first()
        if role is None:
            continue
        for code in codes:
            RolePermission.objects.get_or_create(
                role=role, permission=Permission.objects.get(code=code)
            )


def unseed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in CODES:
        RolePermission.objects.filter(permission__code=code).delete()
        Permission.objects.filter(code=code).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0012_alter_securityevent_event_type"),
        ("appointments", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]