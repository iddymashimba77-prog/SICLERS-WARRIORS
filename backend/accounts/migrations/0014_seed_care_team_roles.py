"""Seed the PSYCHOLOGIST and SOCIAL_SUPPORT care-team roles.

These two roles are *not* doctors and must not inherit doctor privileges by
accident. The temptation with a new clinical role is to copy the DOCTOR row and
delete what looks wrong; that is how a support worker ends up able to write into
a patient chart. So the bundles below are written from the role's actual job:

PSYCHOLOGIST — a clinical professional who treats mental health. Writes clinical
entries and uploads session documents, but only under C15 (clinical relationship
+ consent) and only while APPROVED in the professional registry. Denied
`medications.prescribe`: this system has one prescribing role, and a psychologist
is not it.

SOCIAL_SUPPORT — a care/navigation worker. Coordinates support: conversations,
appointments of their own, education content. Read-only on clinical data, and
only where a patient has granted consent. No chart write, no delete, no
prescribing: default-deny, as matrix rule 1 requires.

Both are `is_system=True, self_registerable=False` (same as DOCTOR): they enter
through administrative assignment plus the professional verification pipeline
(C5), never through `/api/auth/register/`.
"""

from django.db import migrations


COMMON = [
    "ai.use",
    "auth.profile_view",
    "campaigns.view",
    "community.comment",
    "community.create_post",
    "community.report",
    "education.view",
    "notifications.manage_prefs",
    "notifications.view",
]

CARE_TEAM_ROLES = [
    ("PSYCHOLOGIST", "Psychologist"),
    ("SOCIAL_SUPPORT", "Social Support Worker"),
]

ROLE_PERMISSIONS = {
    # Clinical professional, mental-health specialism. Same clinical write set as
    # DOCTOR minus prescribing; read/download still consent-scoped (C2/3).
    "PSYCHOLOGIST": COMMON + [
        "appointments.read",
        "appointments.write_own",
        "chat.send",
        "chat.start",
        "doctors.self_manage",
        "doctors.view",
        "education.publish",
        "medical_records.create",
        "medical_records.download",
        "medical_records.update",
        "medical_records.upload",
        "medical_records.view",
        "patients.records.download",
        "patients.records.read",
        "patients.view",
        "symptoms.record",
    ],
    # Support/navigation. Deliberately has no medical_records.create/update/
    # upload/delete and no medications.*: it coordinates care, it does not author
    # or prescribe it.
    "SOCIAL_SUPPORT": COMMON + [
        "appointments.read",
        "appointments.write_own",
        "chat.send",
        "chat.start",
        "doctors.self_manage",
        "doctors.view",
        "education.publish",
        "medical_records.download",
        "medical_records.view",
        "patients.records.read",
        "patients.view",
    ],
}


def _parts(code):
    split = code.split(".")
    module = split[0]
    resource = split[1] if len(split) > 1 else ""
    action = split[-1]
    return module, resource, action


def seed_care_team_roles(apps, schema_editor):
    Role = apps.get_model("accounts", "Role")
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code, name in CARE_TEAM_ROLES:
        Role.objects.get_or_create(
            code=code,
            defaults={"name": name, "is_system": True},
        )
    for role_code, perm_codes in ROLE_PERMISSIONS.items():
        role = Role.objects.get(code=role_code)
        for perm_code in perm_codes:
            module, resource, action = _parts(perm_code)
            permission, _ = Permission.objects.get_or_create(
                code=perm_code,
                defaults={"module": module, "resource": resource, "action": action},
            )
            RolePermission.objects.get_or_create(role=role, permission=permission)


def unseed_care_team_roles(apps, schema_editor):
    Role = apps.get_model("accounts", "Role")
    Role.objects.filter(code__in=[code for code, _ in CARE_TEAM_ROLES]).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0013_seed_medical_record_permissions"),
    ]

    operations = [
        migrations.RunPython(seed_care_team_roles, unseed_care_team_roles),
    ]