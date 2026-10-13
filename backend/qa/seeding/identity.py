"""Phase 1 — identity: admin, facilities, organizations, users and profiles.

Creates the 25-account matrix for every independently sign-in-capable role,
plus the facility directory and (schema-only) organizations those accounts
attach to. Idempotent via deterministic emails/phones and ``uuid5`` uids.
"""

from __future__ import annotations

import datetime as _dt

from accounts.models import Role, User, UserRole
from donations.models import Organization
from facilities.models import Facility

from .base import (
    ADMIN_GRANTED, CLINIC_SUFFIXES, DEFAULT_PASSWORD, FACILITY_PREFIXES,
    HOSPITAL_SUFFIXES, ORG_PREFIXES, ORG_SUFFIXES, PER_ROLE,
    REGISTRATION_BODIES, ROLE_SEEDS, SELF_REGISTERABLE, SPECIALTIES, TAG,
    email_for, full_name, phone_for, region_city,
)

ADMIN_EMAIL = "admin@sw.local"
ADMIN_PASSWORD = "Admin!2026-Sw"


def ensure_admin(ctx) -> User:
    """Use the pre-existing Super Admin account; create only if absent."""
    admin, created = User.objects.get_or_create(
        email=ADMIN_EMAIL,
        defaults={
            "first_name": "SW", "last_name": "Admin",
            "account_status": "ACTIVE", "is_superuser": True, "is_staff": True,
        },
    )
    if created:
        admin.set_password(ADMIN_PASSWORD)
        admin.save()
    role = Role.objects.get(code="SUPER_ADMIN")
    UserRole.objects.get_or_create(user=admin, role=role)
    ctx.admin = admin
    if created:
        ctx.log(f"- Created Super Admin {ADMIN_EMAIL}")
    else:
        ctx.log(f"- Reused Super Admin {ADMIN_EMAIL}")
    return admin


def _shared_password_hash(ctx) -> str:
    """Hash the shared password once; 275 PBKDF2 passes are needlessly slow."""
    cached = ctx.verified.get("password_hash")
    if cached is None:
        from django.contrib.auth.hashers import make_password
        cached = make_password(ctx.password)
        ctx.verified["password_hash"] = cached
    return cached


def _upsert_user(ctx, role_code: str, index: int) -> User:
    email = email_for(role_code, index)
    phone = phone_for(role_code, index)
    first, last = full_name(ctx.rng)
    user, created = User.objects.get_or_create(
        email=email,
        defaults={
            "phone": phone,
            "first_name": first,
            "last_name": last,
            "account_status": "ACTIVE",
        },
    )
    if created:
        user.password = _shared_password_hash(ctx)
        user.save(update_fields=["password"])
    role = Role.objects.get(code=role_code)
    UserRole.objects.get_or_create(
        user=user, role=role, defaults={"granted_by": ctx.admin},
    )
    ctx.track("users")
    return user


def seed_users(ctx) -> None:
    for role_code in ROLE_SEEDS:
        ctx.users[role_code] = [
            _upsert_user(ctx, role_code, i) for i in range(1, PER_ROLE + 1)
        ]
        ctx.log(f"- {role_code}: {PER_ROLE} accounts")


def _facility_name(ctx, facility_type: str, index: int) -> str:
    prefix = FACILITY_PREFIXES[(index - 1) % len(FACILITY_PREFIXES)]
    if facility_type == "HOSPITAL":
        suffix = HOSPITAL_SUFFIXES[(index - 1) % len(HOSPITAL_SUFFIXES)]
    elif facility_type == "CLINIC":
        suffix = CLINIC_SUFFIXES[(index - 1) % len(CLINIC_SUFFIXES)]
    elif facility_type == "LABORATORY":
        suffix = "Diagnostic Laboratory"
    elif facility_type == "BLOOD_BANK":
        suffix = "Blood Bank"
    else:
        suffix = "Pharmacy"
    return f"{prefix} {suffix} (QA)"


def seed_facilities(ctx) -> None:
    """One operated facility per HOSPITAL / CLINIC account, plus support sites."""
    ctx.facilities.setdefault("HOSPITAL", [])
    ctx.facilities.setdefault("CLINIC", [])
    ctx.facilities.setdefault("LABORATORY", [])
    ctx.facilities.setdefault("BLOOD_BANK", [])
    ctx.facilities.setdefault("PHARMACY", [])

    for role_code, ftype in (("HOSPITAL", "HOSPITAL"), ("CLINIC", "CLINIC")):
        for i, user in enumerate(ctx.users_of(role_code), start=1):
            region, city = region_city(ctx.rng)
            name = _facility_name(ctx, ftype, i)
            facility, _ = Facility.objects.update_or_create(
                registration_number=f"{TAG}-{ftype[:4]}-{i:03d}",
                defaults={
                    "name": f"{name} #{i:02d}",
                    "facility_type": ftype,
                    "region": region,
                    "city": city,
                    "address": f"{city}, {region}, Tanzania (QA test facility)",
                    "operator": user,
                    "is_verified": False,
                },
            )
            ctx.facilities[ftype].append(facility)
            ctx.track("facilities")

    # Unoperated support facilities used as directories / blood banks / labs.
    for i in range(1, 4):
        region, city = region_city(ctx.rng)
        facility, _ = Facility.objects.update_or_create(
            registration_number=f"{TAG}-LAB-{i:03d}",
            defaults={
                "name": f"{FACILITY_PREFIXES[i]} Diagnostic Laboratory (QA) #{i:02d}",
                "facility_type": "LABORATORY", "region": region, "city": city,
                "address": f"{city}, {region}, Tanzania (QA test lab)", "is_verified": True,
            },
        )
        ctx.facilities["LABORATORY"].append(facility)
        ctx.track("facilities")
    for i in range(1, 3):
        region, city = region_city(ctx.rng)
        facility, _ = Facility.objects.update_or_create(
            registration_number=f"{TAG}-BLD-{i:03d}",
            defaults={
                "name": f"{FACILITY_PREFIXES[i + 3]} Blood Bank (QA) #{i:02d}",
                "facility_type": "BLOOD_BANK", "region": region, "city": city,
                "address": f"{city}, {region}, Tanzania (QA test blood bank)", "is_verified": True,
            },
        )
        ctx.facilities["BLOOD_BANK"].append(facility)
        ctx.track("facilities")
    ctx.log(
        f"- facilities: {len(ctx.facilities['HOSPITAL'])} hospitals, "
        f"{len(ctx.facilities['CLINIC'])} clinics, "
        f"{len(ctx.facilities['LABORATORY'])} labs, "
        f"{len(ctx.facilities['BLOOD_BANK'])} blood banks"
    )


def seed_organizations(ctx) -> None:
    for i in range(1, 9):
        name = f"{ORG_PREFIXES[(i - 1) % len(ORG_PREFIXES)]} {ORG_SUFFIXES[(i - 1) % len(ORG_SUFFIXES)]} (QA)"
        org, _ = Organization.objects.update_or_create(
            name=name,
            defaults={
                "org_type": "NGO",
                "contact_email": f"org{i:02d}@qa-demo.example.com",
                "is_verified": True,
                "verified_by": ctx.admin,
            },
        )
        ctx.organizations.append(org)
        ctx.track("organizations")
    ctx.log(f"- organizations: {len(ctx.organizations)}")


def _dob(index: int) -> _dt.date:
    year = 1985 + (index * 3) % 30
    month = 1 + index % 12
    day = 1 + index % 27
    return _dt.date(year, month, day)


def seed_profiles(ctx) -> None:
    from blood_network.models import BloodDonor
    from doctors.models import Doctor
    from patients.models import Patient

    facilities = ctx.all_facilities()
    hospitals = ctx.facilities_of("HOSPITAL")

    # Patients
    for i, user in enumerate(ctx.users_of("PATIENT"), start=1):
        facility = ctx.rng.choice(hospitals) if hospitals else None
        region, city = region_city(ctx.rng)
        Patient.objects.get_or_create(
            user=user,
            defaults={
                "date_of_birth": _dob(i),
                "gender": "FEMALE" if i % 2 else "MALE",
                "genotype": ["SS", "SC", "SS", "SS", "SBetaThal"][i % 5],
                "diagnosis_date": _dob(i) + _dt.timedelta(days=365 * 2),
                "primary_diagnosis": "Sickle cell disease",
                "emergency_contact_name": f"{full_name(ctx.rng)[0]} {full_name(ctx.rng)[1]}",
                "emergency_contact_phone": f"+2557{50 + i:02d}800{i:04d}",
                "emergency_contact_relation": ["PARENT", "SPOUSE", "SIBLING", "GUARDIAN"][i % 4],
                "address_region": region,
                "address_city": city,
                "facility": facility,
                "notes": f"{TAG} demo patient profile.",
            },
        )
        ctx.track("patient_profiles")

    # Blood donors
    groups = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]
    for i, user in enumerate(ctx.users_of("BLOOD_DONOR"), start=1):
        region, city = region_city(ctx.rng)
        BloodDonor.objects.get_or_create(
            user=user,
            defaults={
                "blood_group": ["O+", "O-", "A+", "B+", "A-", "B-"][i % 6],
                "region": region,
                "city": city,
                "is_verified": i <= 20,
            },
        )
        ctx.track("blood_donor_profiles")

    # Professionals (Doctor / Psychologist / Social support)
    type_by_role = {
        "DOCTOR": "DOCTOR", "PSYCHOLOGIST": "PSYCHOLOGIST",
        "SOCIAL_SUPPORT": "SOCIAL_SUPPORT",
    }
    for role_code, ptype in (("DOCTOR", "DOCTOR"), ("PSYCHOLOGIST", "PSYCHOLOGIST"), ("SOCIAL_SUPPORT", "SOCIAL_SUPPORT")):
        for i, user in enumerate(ctx.users_of(role_code), start=1):
            facility = ctx.rng.choice(facilities) if facilities else None
            Doctor.objects.get_or_create(
                user=user,
                defaults={
                    "facility": facility,
                    "license_number": f"{TAG}-{code_abbr(role_code)}-{i:03d}",
                    "specialty": SPECIALTIES[(i - 1) % len(SPECIALTIES)],
                    "registration_body": REGISTRATION_BODIES[(i - 1) % len(REGISTRATION_BODIES)],
                    "professional_type": professional_type_for(role_code),
                    "verification_status": "PENDING",
                    "is_active": True,
                },
            )
            ctx.track("professional_profiles")
    ctx.log("- created patient / donor / professional profiles")


def code_abbr(role_code: str) -> str:
    return {
        "DOCTOR": "LIC", "PSYCHOLOGIST": "PSY", "SOCIAL_SUPPORT": "SSW",
    }.get(role_code, "LIC")


def professional_type_for(role_code: str) -> str:
    return {
        "PSYCHOLOGIST": "PSYCHOLOGIST",
        "SOCIAL_SUPPORT": "SOCIAL_SUPPORT",
    }.get(role_code, "DOCTOR")


def seed(ctx) -> None:
    ctx.log("## Identity")
    ensure_admin(ctx)
    seed_users(ctx)
    seed_facilities(ctx)
    seed_organizations(ctx)
    seed_profiles(ctx)
