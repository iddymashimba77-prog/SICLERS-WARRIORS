"""Seed the approved symptom catalog (Stage 4.6).

Approved source: database-design.md §8.1 / ERD — the symptom_type vocabulary
with the `is_pain_related` marker (0..10 pain scale applies to pain-related
types). SCD-reviewed, group-prefixed vocabulary; the catalog is the approved
read-only reference (`GET /api/symptom-types/`) — never invented client-side.
"""

from django.db import migrations

SYMPTOM_TYPES = [
    # --- Pain group (is_pain_related) ---
    ("pain_crisis", "Painful crisis", True),
    ("pain_chronic", "Chronic pain", True),
    ("pain_joint", "Joint pain", True),
    ("pain_abdominal", "Abdominal pain", True),
    ("pain_chest", "Chest pain", True),
    ("pain_headache", "Headache", True),
    ("muscle_cramp", "Muscle cramp", True),
    # --- Respiratory ---
    ("resp_shortness", "Shortness of breath", False),
    ("resp_cough", "Cough (dry)", False),
    ("resp_wheeze", "Wheezing", False),
    # --- Cardiovascular ---
    ("cv_hypertension", "Raised blood pressure", False),
    ("cv_palpitations", "Palpitations", False),
    # --- Neuro ---
    ("neuro_dizziness", "Dizziness", False),
    ("neuro_paresthesia", "Tingling (paresthesia)", False),
    ("neuro_seizure", "Seizure", False),
    # --- Haematologic ---
    ("hem_jaundice", "Jaundice / yellow eyes", False),
    ("hem_pallor", "Pale skin (pallor)", False),
    ("hem_oedema", "Swelling (oedema)", False),
    # --- GI ---
    ("gi_nausea", "Nausea", False),
    ("gi_vomiting", "Vomiting", False),
    ("gi_diarrhea", "Diarrhoea", False),
    ("gi_constipation", "Constipation", False),
    # --- GU ---
    ("gu_hematuria", "Blood in urine", False),
    ("gu_frequency", "Urinating more often", False),
    # --- Skin / metabolic ---
    ("skin_ulcer", "Leg ulcer", True),
    ("skin_rash", "Rash", False),
    ("meta_appetite", "Poor appetite", False),
]


def seed_symptom_types(apps, schema_editor):
    SymptomType = apps.get_model("medications", "SymptomType")
    for code, name, is_pain_related in SYMPTOM_TYPES:
        SymptomType.objects.get_or_create(
            code=code,
            defaults={"name": name, "is_pain_related": is_pain_related},
        )


def unseed_symptom_types(apps, schema_editor):
    SymptomType = apps.get_model("medications", "SymptomType")
    SymptomType.objects.filter(code__in=[c for c, _, _ in SYMPTOM_TYPES]).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("medications", "0002_medication_events"),
    ]

    operations = [
        migrations.RunPython(seed_symptom_types, unseed_symptom_types),
    ]