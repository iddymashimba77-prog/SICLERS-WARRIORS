"""Seed the branding permission code (Stage 4.31 — Admin Branding).

Approved grant (mirror of the role-permission matrix's system area):
    admin.branding.manage -> SUPER_ADMIN     (logo upload / alt text / remove)

Deny-by-default holds: only the explicit cell below is seeded; every other
role is denied until the matrix is amended. The write surface gated by this
code also applies the MFA step-up boundary (``accounts.mfa``), so a
SUPER_ADMIN with MFA enabled must pass the step-up challenge before the
platform logo can be replaced.
"""

from django.db import migrations


def seed_branding(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    Role = apps.get_model("accounts", "Role")
    RolePermission = apps.get_model("accounts", "RolePermission")

    permission, _created = Permission.objects.get_or_create(
        code="admin.branding.manage",
        defaults={
            "module": "admin",
            "resource": "branding",
            "action": "manage",
        },
    )
    super_admin = Role.objects.get(code="SUPER_ADMIN")
    RolePermission.objects.get_or_create(
        role=super_admin,
        permission=permission,
    )


def unseed_branding(apps, schema_editor):
    Permission = apps.get_model("accounts", "Permission")
    Permission.objects.filter(code="admin.branding.manage").delete()


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0001_initial"),
        ("core", "0002_app_branding"),
    ]

    operations = [
        migrations.RunPython(seed_branding, reverse_code=unseed_branding),
    ]