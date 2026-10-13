"""Shared constants + helpers for the Tanzania QA seeding package.

Design:
* **Deterministic** — a fixed RNG seed and ``uuid5`` ids mean re-running the
  command produces the same logical rows (idempotent), never duplicates.
* **Tagged** — every identity uses the ``SWQA-TZ-2026`` marker so the dataset is
  trivially identifiable in the dev database.
* **Atomic** — the caller wraps execution in one transaction; a failure rolls
  the whole run back.
"""

from __future__ import annotations

import random
import uuid
from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# Identity / marker
# ---------------------------------------------------------------------------

TAG = "SWQA-TZ-2026"
# A stable namespace so ``uuid_for("appointment", 3)`` is the *same* UUID on
# every run — that is what makes ``update_or_create(uid=...)`` idempotent.
_NS = uuid.UUID("f1e2d3c4-b5a6-4788-9911-aabbccddeeff")

#: Default password for every seeded account. Overridable via
#: ``QA_SEED_PASSWORD`` env var or ``--password``; documented in the QA report.
DEFAULT_PASSWORD = "SwQa!2026-Tz"

#: Primary (independently counted) roles we create 25 accounts for.
ROLE_SEEDS = [
    "PATIENT",
    "CAREGIVER",
    "BLOOD_DONOR",
    "DOCTOR",
    "PSYCHOLOGIST",
    "SOCIAL_SUPPORT",
    "HOSPITAL",
    "CLINIC",
    "ORGANIZATION",
    "FINANCIAL_DONOR",
    "HEALTHCARE_STAFF",
]

#: Self-registerable roles (normal signup path) — everything else is granted.
SELF_REGISTERABLE = [
    "PATIENT", "CAREGIVER", "BLOOD_DONOR", "DOCTOR", "PSYCHOLOGIST",
    "SOCIAL_SUPPORT", "HOSPITAL", "CLINIC", "ORGANIZATION",
]
#: Granted (admin) only — created as standalone accounts for QA coverage.
ADMIN_GRANTED = ["FINANCIAL_DONOR", "HEALTHCARE_STAFF"]

PER_ROLE = 25


def uuid_for(*parts) -> uuid.UUID:
    """Deterministic UUID for a logical row within the tagged dataset."""
    return uuid.uuid5(_NS, ":".join(str(p) for p in parts))


# ---------------------------------------------------------------------------
# Tanzania-flavoured reference data
# ---------------------------------------------------------------------------

FIRST_NAMES = [
    "Amani", "Baraka", "Neema", "Rehema", "Zawadi", "Fatuma", "Halima", "Juma",
    "Hamisi", "Said", "Salma", "Upendo", "Mwajuma", "Asha", "Joseph", "Grace",
    "Elias", "Daudi", "Amina", "Mariam", "Emmanuel", "Frank", "Tumaini",
    "Zainabu", "Rashid", "Hawa", "Salum", "Nasra", "Peter", "Anna", "Hamza",
    "Rehema", "Godfrey", "Judith", "Musa", "Bahati", "Subira", "Ibrahim",
    "Lucy", "Agnes", "Deogratius", "Ester", "Jackson", "Furaha", "Zuhura",
    "Bakari", "Sophia", "Michael", "Theresia", "Khamis",
]

LAST_NAMES = [
    "Mwakyusa", "Kimaro", "Mushi", "Massawe", "Shirima", "Lyimo", "Mwansasu",
    "Kilonzo", "Mwalinga", "Mfaume", "Nyambari", "Mwaipungu", "Kessy",
    "Machuve", "Swai", "Mmari", "Mhando", "Ngowi", "Kilenga", "Bakari",
    "Juma", "Salehe", "Mwashiuya", "Mgeni", "Mbwana", "Rashid", "Abdallah",
    "Hamisi", "Suleiman", "Mollel", "Nyerere", "Mfilinge", "Kibona", "Lema",
    "Uriyo", "Temba", "Mkude", "Chacha", "Mwangosi", "Mbaruku",
]

#: (region, [cities]) — real Tanzanian regions with plausible municipalities.
REGIONS = [
    ("Dar es Salaam", ["Kinondoni", "Ilala", "Temeke", "Ubungo", "Kigamboni"]),
    ("Mwanza", ["Ilemela", "Nyamagana", "Sengerema"]),
    ("Arusha", ["Arusha City", "Meru", "Karatu"]),
    ("Dodoma", ["Dodoma City", "Chamwino"]),
    ("Mbeya", ["Mbeya City", "Mbarali"]),
    ("Morogoro", ["Morogoro Urban", "Kilosa"]),
    ("Tanga", ["Tanga City", "Muheza"]),
    ("Kilimanjaro", ["Moshi", "Hai", "Rombo"]),
    ("Zanzibar", ["Mjini Magharibi", "Kaskazini A"]),
    ("Iringa", ["Iringa Urban", "Mufindi"]),
    ("Kigoma", ["Kigoma-Ujiji"]),
    ("Tabora", ["Tabora Urban"]),
]

FACILITY_PREFIXES = [
    "Tumaini", "Baraka", "Amani", "Upendo", "Salama", "Neema", "Mkombozi",
    "Faraja", "Nuru", "Ubuntu", "Afya", "Pamoja", "Imara", "Tunaweza",
    "Huru", "Fikra", "Maendeleo", "Zawadi", "Hekima", "Jasiri",
]

HOSPITAL_SUFFIXES = ["Referral Hospital", "Regional Hospital", "District Hospital", "Mission Hospital"]
CLINIC_SUFFIXES = ["Medical Centre", "Polyclinic", "Health Centre", "Clinic"]

ORG_PREFIXES = ["Tanzania Sickle Cell", "Upendo Health", "Mkombozi", "Faraja", "Neema", "Pamoja", "Tumaini", "Afya"]
ORG_SUFFIXES = ["Foundation", "Trust", "Charitable Trust", "Association", "Initiative", "Network"]

SPECIALTIES = [
    "Haematology", "Paediatric Haematology", "Paediatrics", "Internal Medicine",
    "General Practice", "Emergency Medicine", "Family Medicine",
    "Haematology & Oncology", "Clinical Psychology", "Psychiatry",
    "Counselling Psychology", "Social Work",
]
REGISTRATION_BODIES = [
    "Medical Council of Tanganyika", "Tanzania Medical Council",
    "Nursing and Midwifery Council of Tanzania",
]

EDUCATION_CATEGORIES = [
    ("SICKLE_BASICS", "Sickle Cell Basics", 10),
    ("NUTRITION", "Nutrition & Hydration", 20),
    ("PAIN_MANAGEMENT", "Pain & Crisis Management", 30),
    ("GENETICS", "Genetics & Inheritance", 40),
    ("WELLBEING", "Emotional Wellbeing", 50),
    ("SCHOOL_LIFE", "School & Daily Life", 60),
    ("BLOOD_DONATION", "Blood Donation Awareness", 70),
    ("PREGNANCY", "Pregnancy & Newborn Care", 80),
]

NEWS_ITEMS = [
    ("Red Cross Tanzania partners for a national blood drive during Sickle Cell Awareness Month", "BLOOD"),
    ("New paediatric haematology unit opens at Mwanza referral hospital", "HEALTH"),
    ("Ministry of Health expands newborn sickle cell screening to twelve regions", "HEALTH"),
    ("Upendo Foundation launches school scholarships for warriors", "FUNDRAISING"),
    ("World Sickle Cell Day: community walk draws thousands in Dar es Salaam", "EVENTS"),
    ("Nutrition guide for sickle cell warriors released in Swahili", "EDUCATION"),
    ("Blood donation drive reaches 1,000 units in Arusha", "BLOOD"),
    ("Telehealth clinics bring haematology care to rural Dodoma", "HEALTH"),
    ("New peer-support circles launch across Mwanza and Mbeya", "COMMUNITY"),
    ("Hydroxyurea access programme expands to regional hospitals", "ANNOUNCEMENTS"),
    ("Fundraising drive for paediatric gene therapy research passes half its goal", "FUNDRAISING"),
    ("Annual sickle cell scientific conference set for Arusha", "EVENTS"),
]

TICKER_MESSAGES = [
    ("INFO", "Welcome to the Sickler's Warriors test community (QA-TZ-2026)."),
    ("BLOOD", "O- blood is needed urgently at Kijichi Referral Hospital."),
    ("URGENT", "Emergency: increased demand for blood at Mwanza region hospitals."),
    ("EVENT", "Community awareness walk this Saturday in Dar es Salaam."),
    ("DONATION", "Every TZS 1,000 helps a family access care. Donate today."),
    ("SUCCESS", "Thank you — 500 units of blood collected this month!"),
]

COMMUNITY_TITLES = [
    "Living well with sickle cell: my daily routine",
    "Tips for managing pain crises at home",
    "How do you stay hydrated during hot weather?",
    "Feeling grateful for my care team",
    "Newly diagnosed — looking for advice",
    "School and sickle cell: how do you cope?",
    "Nutrition wins: iron-rich local foods",
    "Breathing exercises that helped me",
    "Preparing for a hospital visit",
    "One year since starting hydroxyurea",
]

COMMENT_TEXTS = [
    "Thank you for sharing this — very helpful.",
    "Sending strength and prayers.",
    "We do the same in our family.",
    "This is so important to talk about.",
    "Has anyone tried this with a child?",
    "Stay strong, warrior!",
    "Great tips, I'll try them.",
    "Wishing you good health.",
]

MEDICATIONS = [
    ("Hydroxyurea", "Hydroxycarbamide", "500 mg", "Oral, once daily"),
    ("Folic Acid", "Folic Acid", "5 mg", "Oral, once daily"),
    ("Penicillin V", "Phenoxymethylpenicillin", "250 mg", "Oral, twice daily"),
    ("Paracetamol", "Acetaminophen", "500 mg", "Oral, as needed"),
    ("Ibuprofen", "Ibuprofen", "400 mg", "Oral, three times daily"),
    ("Ibuprofen", "Ibuprofen", "200 mg", "Oral, once daily"),
]

MED_NOTES = [
    "Take with food.",
    "Take at the same time each day.",
    "Drink plenty of water.",
    "Do not skip doses.",
]

SYMPTOM_NOTES = [
    "Generalised body pain, worse in joints.",
    "Chest tightness and shortness of breath.",
    "Mild fever, managed at home.",
    "Headache and fatigue after school.",
    "Abdominal discomfort after meals.",
]

NEWS_BODY = (
    "Sickle cell disease affects thousands of families across Tanzania. This "
    "QA-tagged article is part of the SWQA-TZ-2026 demonstration dataset and "
    "describes a fictional programme for testing the public news experience. "
    "Real care decisions must always be made with a qualified clinician."
)

EDU_BODY = (
    "This is QA demo content generated for the Sickler's Warriors test dataset "
    "(SWQA-TZ-2026). It explains sickle cell concepts in plain language for "
    "community education testing only and is not medical advice."
)


# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------


@dataclass
class SeedContext:
    """Mutable bag threaded through every seeding phase."""

    tag: str = TAG
    password: str = DEFAULT_PASSWORD
    rng: random.Random = field(default_factory=lambda: random.Random(20261012))
    admin: object = None

    facilities: dict = field(default_factory=dict)   # facility_type -> [Facility]
    users: dict = field(default_factory=dict)         # role_code -> [User]
    organizations: list = field(default_factory=list)
    counts: dict = field(default_factory=dict)
    report_lines: list = field(default_factory=list)
    verified: dict = field(default_factory=dict)   # scratch bookkeeping

    def users_of(self, role: str) -> list:
        return self.users.get(role, [])

    def facilities_of(self, facility_type: str) -> list:
        return self.facilities.get(facility_type, [])

    def all_facilities(self) -> list:
        out = []
        for rows in self.facilities.values():
            out.extend(rows)
        return out

    def track(self, key: str, n: int = 1):
        self.counts[key] = self.counts.get(key, 0) + n

    def log(self, line: str):
        self.report_lines.append(line)


def full_name(rng: random.Random) -> tuple[str, str]:
    return rng.choice(FIRST_NAMES), rng.choice(LAST_NAMES)


def region_city(rng: random.Random) -> tuple[str, str]:
    region, cities = rng.choice(REGIONS)
    return region, rng.choice(cities)


def email_for(role: str, index: int) -> str:
    return f"{TAG.lower()}-{role.lower().replace('_', '-')}-{index:02d}@qa-demo.example.com"


def phone_for(role: str, index: int) -> str:
    role_ord = (ROLE_SEEDS.index(role) + 1) if role in ROLE_SEEDS else 99
    return f"+2557{role_ord:02d}9{index:05d}"


def split_name(name: str) -> tuple[str, str]:
    first, _, last = name.partition(" ")
    return first, (last or "Mwakyusa")
