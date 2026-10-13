"""Canonical national facility reference data (Tanzania).

Source of truth for the bootstrap directory used by the seed migration and by
``manage.py seed_facility_directory``.

Only fields verifiable from public reference material are recorded: name,
facility type, region and city. Street addresses, phone numbers and
registration numbers are intentionally absent — a fabricated registration
number would let an unverified organisation present itself as a licensed
facility, which is exactly the control ``is_verified`` exists to prevent.

Rows are ``(name, facility_type, region, city)`` and are keyed on
``(name, city)`` so loading is idempotent and can never overwrite a row an
officer has since edited.
"""

NATIONAL_REFERRAL_FACILITIES = [
    ("Muhimbili National Hospital", "HOSPITAL", "Dar es Salaam", "Dar es Salaam"),
    ("Muhimbili University Health, Referral, Academic and Research Centre",
     "HOSPITAL", "Dar es Salaam", "Dar es Salaam"),
    ("Muhimbili Orthopaedic Institute", "HOSPITAL", "Dar es Salaam", "Dar es Salaam"),
    ("Tanzania National Blood Transfusion Service", "BLOOD_BANK", "Dar es Salaam", "Dar es Salaam"),
    ("Bugando Medical Centre", "HOSPITAL", "Mwanza", "Mwanza"),
    ("Kilimanjaro Christian Medical Centre", "HOSPITAL", "Kilimanjaro", "Moshi"),
    ("Southern Highlands Referral Hospital", "HOSPITAL", "Mbeya", "Mbeya"),
    ("Arusha Regional Referral Hospital", "HOSPITAL", "Arusha", "Arusha"),
    ("Tanga Regional Referral Hospital", "HOSPITAL", "Tanga", "Tanga"),
    ("Benjamin Mkapa Hospital", "HOSPITAL", "Dodoma", "Dodoma"),
    ("Kagera Referral Hospital", "HOSPITAL", "Kagera", "Bukoba"),
    ("Mnara Mwalimu Hospital", "HOSPITAL", "Zanzibar", "Zanzibar"),
]

CSV_HEADER = ["name", "facility_type", "region", "city"]
