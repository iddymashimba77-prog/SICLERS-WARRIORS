"""Seed approved donation/payment permissions (Stage 4.12).

Approved codes from `docs/sdlc/03-system-design/role-permission-matrix.md`
§3.10/§3.11:

    campaigns.create   SUPER_ADMIN/ADMIN (A), PATIENT/ORGANIZATION (C11)
    campaigns.view     all roles (A)
    campaigns.verify   SUPER_ADMIN/ADMIN/VERIFICATION_OFFICER (A)
    donations.create   all roles (A)
    donations.view     SUPER_ADMIN/ADMIN/FINANCIAL_DONOR/ORGANIZATION (A)
    donations.refund   SUPER_ADMIN/ADMIN (A)
    payments.view      SUPER_ADMIN/ADMIN/FINANCIAL_DONOR/ORGANIZATION (A)
    payments.refund    SUPER_ADMIN/ADMIN (A)
    payments.verify    service-internal (no role)

C11 ("verified before public fundraising", BR-007) is a workflow constraint
(donate only to ACTIVE campaigns), enforced in the service layer — not an extra
grant row. ``payments.verify`` is registered for traceability but granted to no
role: webhooks authenticate by HMAC signature (security-design §21/§22).
"""

from django.db import migrations

CODES = [
    "campaigns.create",
    "campaigns.view",
    "campaigns.verify",
    "donations.create",
    "donations.view",
    "donations.refund",
    "payments.view",
    "payments.refund",
    "payments.verify",
]

ALL_ROLES = [
    "SUPER_ADMIN", "ADMIN", "VERIFICATION_OFFICER", "MODERATOR", "DOCTOR",
    "HEALTHCARE_STAFF", "HOSPITAL", "PATIENT", "CAREGIVER", "BLOOD_DONOR",
    "FINANCIAL_DONOR", "ORGANIZATION",
]

ROLE_GRANTS = {
    **{role: ["campaigns.view", "donations.create"] for role in ALL_ROLES},
    "SUPER_ADMIN": [
        "campaigns.view", "campaigns.verify", "donations.create", "donations.view",
        "donations.refund", "payments.view", "payments.refund",
    ],
    "ADMIN": [
        "campaigns.view", "campaigns.verify", "donations.create", "donations.view",
        "donations.refund", "payments.view", "payments.refund",
    ],
    "VERIFICATION_OFFICER": ["campaigns.view", "campaigns.verify", "donations.create"],
    "PATIENT": ["campaigns.view", "campaigns.create", "donations.create"],
    "ORGANIZATION": [
        "campaigns.view", "campaigns.create", "donations.create", "donations.view",
        "payments.view",
    ],
    "FINANCIAL_DONOR": [
        "campaigns.view", "donations.create", "donations.view", "payments.view",
    ],
}

# ``payments.verify`` intentionally has no grant rows (service-internal).


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
            RolePermission.objects.get_or_create(
                role=role, permission=Permission.objects.get(code=code),
            )


def unseed(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    for code in CODES:
        RolePermission.objects.filter(permission__code=code).delete()
        Permission.objects.filter(code=code).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("donations", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]