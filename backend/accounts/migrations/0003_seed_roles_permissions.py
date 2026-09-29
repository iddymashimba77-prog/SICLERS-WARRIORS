"""Role & default-permission seed (Stage 4.4, RBAC foundation).

Why a *data* migration (and not an API/exec):

* §32 migration strategy (a) — migration ordering is the approved path to a
  fresh/empty database (used by config/settings/ephemeral_test.py) and is
  identical whether the target is the ephemeral SQLite gate or the future
  Postgres `sicklers` DB. No superuser / DROP-DATABASE action is required to
  apply this seed.
* `/api/auth/register/` (RegisterSerializer.create) issues one approved role
  via `Role.objects.get(code=...)`; without a seeded `roles` row the endpoint
  cannot even evaluate the self-registerable gate. This migration guarantees
  the 16 approved areas + the approved role set exist before any API call.

The permission bundle below is drawn from the APPROVED SSoT
`docs/sdlc/03-system-design/role-permission-matrix.md`:
* Codes are `<module>.<resource>.<action>` (e.g. `patients.records.read`).
* Columns follow the 16 functional areas; cell values ALLOW / DENY /
  CONDITIONAL. Only ALLOW (and conditional-scope cells whose conditions the
  *permission gate itself* must enforce later) are seeded here; DENY-by-default
  means anything not seeded is denied.
* Object-level conditions (C2 consent, C3 ownership, C7 facility context) are
  NOT expressible as a single column; they are enforced/re-audited in the
  view/permission layer (`accounts/permissions.py`) on top of this seed.
"""

from django.db import migrations


APPROVED_ROLES = [
    # code, name, is_system, self_registerable
    ("SUPER_ADMIN", "Super Administrator", True, False),
    ("ADMIN", "Administrator", True, False),
    ("VERIFICATION_OFFICER", "Verification Officer", True, False),
    ("MODERATOR", "Moderator", True, False),
    ("DOCTOR", "Doctor", True, False),
    ("HEALTHCARE_STAFF", "Healthcare Staff", True, False),
    ("HOSPITAL", "Hospital", True, False),
    ("PATIENT", "Patient", True, True),
    ("CAREGIVER", "Caregiver", True, True),
    ("BLOOD_DONOR", "Blood Donor", True, False),
    ("FINANCIAL_DONOR", "Financial Donor", True, False),
    ("ORGANIZATION", "Organization", True, False),
]

# ALLOW cells from the approved matrix (role_adjective non-CONDITIONAL);
# DENY cells are *not inserted* — the LSAM does not grant what was not
# approved, keeping the access surface default-deny.
ROLE_PERMISSIONS = {
    "SUPER_ADMIN": [
        "admin.system.manage",
        "admin.roles.manage", "admin.permissions.manage",
        "admin.users.manage", "admin.audit.read", "admin.audit.export",
        "admin.content.moderate",
        "patients.records.read", "patients.records.download",
    ],
    "ADMIN": [
        "admin.system.manage", "admin.roles.manage", "admin.users.manage",
        "admin.audit.read", "admin.content.moderate",
    ],
    "VERIFICATION_OFFICER": [
        "verification.doctors.approve", "verification.doctors.reject",
        "verification.donors.approve", "verification.donors.reject",
        "verification.blood_requests.approve",
        "verification.blood_requests.reject",
        "verification.campaigns.approve", "verification.campaigns.reject",
    ],
    "MODERATOR": [
        "community.content.moderate",
    ],
    "DOCTOR": [
        "patients.records.read", "patients.records.download",
        "medications.prescribe", "symptoms.record", "consents.verify",
    ],
    "HEALTHCARE_STAFF": [
        "appointments.manage", "patients.records.read",
        "blood.schedule", "emergency.handle",
    ],
    "HOSPITAL": [
        "patients.records.read", "blood.schedule", "campaigns.manage",
    ],
    "PATIENT": [
        "patients.records.read", "patients.records.manage",
        "symptoms.record", "consents.manage", "blood.donate",
    ],
    "CAREGIVER": [
        "patients.records.read",
    ],
    "BLOOD_DONOR": [
        "blood.donate", "blood.requests.view",
    ],
    "FINANCIAL_DONOR": [
        "donations.made", "campaigns.view",
    ],
    "ORGANIZATION": [
        "campaigns.manage", "donations.manage",
    ],
}


def _parts(code):
    split = code.split(".")
    module, resource = split[0], split[1] if len(split) > 1 else ""
    action = split[-1]
    return module, resource, action


def seed_roles(apps, schema_editor):
    Role = apps.get_model("accounts", "Role")
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code, name, is_system, self_registerable in APPROVED_ROLES:
        role, _ = Role.objects.get_or_create(
            code=code,
            defaults={"name": name, "is_system": is_system},
        )
    for role_code, perms in ROLE_PERMISSIONS.items():
        role = Role.objects.get(code=role_code)
        for perm_code in perms:
            module, resource, action = _parts(perm_code)
            permission, _ = Permission.objects.get_or_create(
                code=perm_code,
                defaults={"module": module, "resource": resource, "action": action},
            )
            RolePermission.objects.get_or_create(role=role, permission=permission)


def unseed_roles(apps, schema_editor):
    Role = apps.get_model("accounts", "Role")
    Role.objects.filter(code__in=[r[0] for r in APPROVED_ROLES]).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0002_onetimetoken"),
    ]

    operations = [
        migrations.RunPython(seed_roles, unseed_roles),
    ]
