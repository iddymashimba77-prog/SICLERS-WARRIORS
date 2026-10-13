"""Seed the CLINIC facility role (C7 facility-operation surface).

The approved facility registry (Stage 4.8) grants ``facilities.self_manage`` to
HOSPITAL operators. CLINIC is its small-facility counterpart: it keeps its own
identity code (role-aware navigation, the open-registration card) but exercises
exactly HOSPITAL's operating bundle. Rather than snapshot permissions here —
which would silently drift each time a later seed migration widens HOSPITAL's
grant table — CLINIC is declared a *grant alias* of HOSPITAL in the role model
(``ROLE_GRANT_ALIASES``), and this migration only creates the role row plus an
explicit ``facilities.self_manage`` operator capability for reviewer clarity.

A supervisor can later widen or narrow the bundle per-facility-type by editing
the grant table; the endpoint matrix does not change.
"""

from django.db import migrations


CLINIC_ROLE = ("CLINIC", "Clinic")
SELF_MANAGE = "facilities.self_manage"


def seed_clinic_role(apps, schema_editor):
    Role = apps.get_model("accounts", "Role")
    Permission = apps.get_model("accounts", "Permission")
    RolePermission = apps.get_model("accounts", "RolePermission")
    clinic, _ = Role.objects.get_or_create(
        code=CLINIC_ROLE[0], defaults={"name": CLINIC_ROLE[1], "is_system": True}
    )
    module, resource = SELF_MANAGE.split(".")
    permission, _ = Permission.objects.get_or_create(
        code=SELF_MANAGE,
        defaults={"module": module, "resource": resource, "action": resource},
    )
    RolePermission.objects.get_or_create(role=clinic, permission=permission)


def unseed_clinic_role(apps, schema_editor):
    Role = apps.get_model("accounts", "Role")
    Role.objects.filter(code=CLINIC_ROLE[0]).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0015_merge_20261005_1201"),
    ]

    operations = [
        migrations.RunPython(seed_clinic_role, unseed_clinic_role),
    ]