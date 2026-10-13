"""Phase 12 — write the QA reports under ``backend/qa/reports/``.

The numbers are read back from the database (not from in-memory counters), so the
reports describe what is actually persisted and stay honest across re-runs.
"""

from __future__ import annotations

import datetime as _dt
from pathlib import Path

from accounts.models import User
from blood_network.models import BloodDonationEvent, BloodMatch, BloodRequest
from community.models import Comment, CommunityPost, Reaction, Report as CommunityReport
from content.models import NewsArticle, TickerAnnouncement
from doctors.models import Doctor
from donations.models import Campaign, Donation, PaymentTransaction, Refund
from education.models import EducationalContent
from emergencies.models import EmergencyAccessGrant, EmergencyRequest, EmergencyResponder
from facilities.models import Facility
from notifications.models import Notification, NotificationPreference, PushDevice
from patients.models import Patient

from .base import ROLE_SEEDS, TAG

REPORTS_DIR = Path(__file__).resolve().parents[1] / "reports"

ACCOUNT_GROUPS = [
    ("Patients", "PATIENT"),
    ("Caregivers", "CAREGIVER"),
    ("Blood donors", "BLOOD_DONOR"),
    ("Doctors", "DOCTOR"),
    ("Psychologists", "PSYCHOLOGIST"),
    ("Social support", "SOCIAL_SUPPORT"),
    ("Hospitals", "HOSPITAL"),
    ("Clinics", "CLINIC"),
    ("Organizations", "ORGANIZATION"),
    ("Financial donors", "FINANCIAL_DONOR"),
    ("Healthcare staff", "HEALTHCARE_STAFF"),
]


def _count(model, **filters):
    return model.objects.filter(**filters).count()


def _write(name: str, text: str):
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    (REPORTS_DIR / name).write_text(text.rstrip() + "\n", encoding="utf-8")


def _dataset_facts() -> dict:
    return {
        "Users (all tagged)": _count(User, email__startswith=TAG.lower()),
        "Facilities": _count(Facility, registration_number__startswith=TAG),
        "Doctor/professional profiles": _count(Doctor),
        "Patient profiles": _count(Patient),
        "Appointments": _count(__import__("appointments.models", fromlist=["ClinicAppointment"]).ClinicAppointment),
        "Clinical encounters": _count(__import__("medical_records.models", fromlist=["ClinicalEncounter"]).ClinicalEncounter),
        "Medical records": _count(__import__("medical_records.models", fromlist=["MedicalRecord"]).MedicalRecord),
        "Medications": _count(__import__("medications.models", fromlist=["Medication"]).Medication),
        "Blood requests": _count(BloodRequest),
        "Blood matches": _count(BloodMatch),
        "Blood donations": _count(BloodDonationEvent),
        "Community posts": _count(CommunityPost),
        "Comments": _count(Comment),
        "Reactions": _count(Reaction),
        "Community reports": _count(CommunityReport),
        "News articles": _count(NewsArticle),
        "Ticker announcements": _count(TickerAnnouncement),
        "Education content": _count(EducationalContent),
        "Campaigns": _count(Campaign),
        "Donations (financial)": _count(Donation),
        "Payment transactions": _count(PaymentTransaction),
        "Refunds": _count(Refund),
        "Emergency requests": _count(EmergencyRequest),
        "Emergency responders": _count(EmergencyResponder),
        "Emergency access grants": _count(EmergencyAccessGrant),
        "Notifications": _count(Notification),
        "Notification preferences": _count(NotificationPreference),
        "Push devices": _count(PushDevice),
    }


def _role_test_accounts():
    lines = [
        f"# Role test accounts — {TAG}",
        "",
        "Synthetic, self-contained accounts created only in the local development "
        "database for QA. Emails follow `swqa-tz-2026-<role>-<NN>@qa-demo.example.com`.",
        "",
        "**Shared password for every seeded account:** `SwQa!2026-Tz`",
        "(override with `--password` or `QA_SEED_PASSWORD`; documented here only — "
        "never commit it to application config).",
        "",
        "| Group | Role code | Sign-in | Self-registerable | Accounts |",
        "| --- | --- | --- | --- | --- |",
    ]
    for label, role in ACCOUNT_GROUPS:
        count = _count(User, email__startswith=f"{TAG.lower()}-{role.lower().replace('_','-')}-")
        lines.append(
            f"| {label} | `{role}` | `/api/auth/login/` | "
            f"{'yes' if role in ROLE_SEEDS and role not in ('FINANCIAL_DONOR','HEALTHCARE_STAFF') else 'admin-granted'} | "
            f"{count} |"
        )
    lines += [
        "",
        "The 9 self-registerable roles use the normal sign-up path; `FINANCIAL_DONOR` "
        "and `HEALTHCARE_STAFF` are created as standalone accounts because they are "
        "granted by an admin but can still sign in (this is the documented 11-role "
        "counting decision: 11 × 25 = 275 accounts).",
        "",
    ]
    return "\n".join(lines)


def _role_test_results(ctx):
    login = ctx.verified.get("login", {})
    lines = [
        f"# Role test results — {TAG}",
        "",
        f"- Generated: {_dt.datetime.now().isoformat(timespec='seconds')}",
        f"- Login endpoint: `POST /api/auth/login/` (`email_or_phone`, `password`)",
        f"- Result: **{login.get('ok', 0)}/{login.get('total', 0)} accounts authenticated**",
        "",
        "| Role | Accounts | Logged in |",
        "| --- | --- | --- |",
    ]
    for role, data in (login.get("by_role") or {}).items():
        lines.append(f"| `{role}` | {data['total']} | {data['ok']} |")
    failures = login.get("failures") or []
    lines += ["", f"Failures: {len(failures)}"]
    for failure in login.get("failures", []):
        lines.append(f"- {failure}")
    lines += [
        "",
        "## Workflow outcomes (persisted via the real admin APIs)",
        "",
        "| Resource | State | Count |",
        "| --- | --- | --- |",
    ]
    for status in ["APPROVED", "REJECTED", "PENDING", "SUSPENDED"]:
        lines.append(f"| Doctors | {status} | {_count(Doctor, verification_status=status)} |")
    lines.append(f"| Facilities | verified | {_count(Facility, is_verified=True)} |")
    lines.append(f"| Facilities | unverified | {_count(Facility, is_verified=False)} |")
    for status in ["PENDING_VERIFICATION", "ACTIVE", "REJECTED", "MATCHED", "FULFILLED"]:
        lines.append(f"| Blood requests | {status} | {_count(BloodRequest, status=status)} |")
    for status in ["PENDING_VERIFICATION", "ACTIVE", "REJECTED", "CLOSED"]:
        lines.append(f"| Campaigns | {status} | {_count(Campaign, status=status)} |")
    lines.append(f"| Education content | PUBLISHED | {_count(EducationalContent, status='PUBLISHED')} |")
    lines.append("")
    return "\n".join(lines)


def _dashboard_data_audit():
    facts = _dataset_facts()
    lines = [
        f"# Dashboard data audit — {TAG}",
        "",
        "The admin dashboard aggregates live source tables (no snapshot rows are "
        "required). The volumes below are what back each panel:",
        "",
        "| Data set | Rows |",
        "| --- | --- |",
    ]
    for key, value in _dataset_facts().items():
        lines.append(f"| {key} | {value} |")
    lines += [
        "",
        "Pending-verification queues exercised by the API phase:",
        f"- Doctors left decided/approved: {_count(Doctor, verification_status='APPROVED')}",
        f"- Blood requests still pending: {_count(BloodRequest, status='PENDING_VERIFICATION')}",
        f"| Campaigns still pending: {_count(Campaign, status='PENDING_VERIFICATION')}",
        "",
    ]
    return "\n".join(lines)


def _defects_and_fixes(ctx):
    return "\n".join([
        f"# Defects & fixes — {TAG}",
        "",
        "## Findings",
        "",
        "1. **Notification type mismatch (fixed).** The canonical type is `APPOINTMENT` (not "
        "`APPOINTMENT_REMINDER`). Updated `notifications/reminders.py` and "
        "`appointments/tests.py` to use the canonical enum.",
        "",
        "## Seeding defects found and fixed during this run",
        "1. `ClinicAppointment.created_by` is `NOT NULL` — appointments now set the "
        "patient as booker.",
        "2. `ClinicAppointment` seeding produced a null `scheduled_at`; replaced with "
        "a real computed datetime.",
        "3. `EmergencyRequest.patient` / `EmergencyAccessGrant.patient` reference "
        "`User`, not `Patient` — corrected.",
        "4. `relationships` phase iterated a generator of querysets — fixed to a "
        "materialised `Patient` list.",
        "5. Shared PBKDF2 hashing per account caused a >300s timeout; hashing is now "
        "computed once and reused for all accounts.",
        "",
    ])


def _dataset_doc():
    lines = [
        f"# Tanzania test dataset — {TAG}",
        "",
        "## Shape",
        "- Seeded by `python manage.py seed_tanzania_qa` (idempotent, single transaction).",
        f"- Every synthetic identity is tagged `{TAG}`; facility/org names carry a `(QA)` "
        "suffix and registration numbers are prefixed with the tag.",
        "- Deterministic UUIDs (`uuid5`) and emails/phones make re-runs update in place "
        "rather than duplicate.",
        "- Tanzanian names, regions/cities, TZS amounts; synthetic organisations only.",
        "",
        "## Row counts (persisted)",
        "| Entity | Count |",
        "| --- | --- |",
    ]
    for key, value in _dataset_facts().items():
        lines.append(f"| {key} | {value} |")
    lines += [
        "",
        "## Safety",
        "- No real SMS/email/payments are sent: notifications are rows, payment "
        "transactions carry synthetic redacted payloads.",
        "- No destructive operation: a single `transaction.atomic()` writes and rolls "
        "back the whole run on failure; nothing truncates or deletes user data.",
        "",
    ]
    return "\n".join(lines)


def _final_summary(ctx):
    login = ctx.verified.get("login", {})
    lines = [
        f"# Final QA summary — {TAG}",
        "",
        f"- Generated: {_dt.datetime.now().isoformat(timespec='seconds')}",
        f"- Accounts seeded: {_count(User, email__startswith=TAG.lower())}",
        f"- Logins verified: {login.get('ok', 0)}/{login.get('total', 0)}",
        f"- Doctor decisions: {_count(Doctor, verification_status='APPROVED')} approved / "
        f"{_count(Doctor, verification_status='REJECTED')} rejected",
        f"- Blood requests decided: {_count(BloodRequest, status='ACTIVE')} active / "
        f"{_count(BloodRequest, status='REJECTED')} rejected",
        f"- Campaigns: {_count(Campaign, status='ACTIVE')} active / "
        f"{_count(Campaign, status='REJECTED')} rejected",
        f"- Education published: {_count(EducationalContent, status='PUBLISHED')}",
        "",
        "## Deliverables",
        "- `role_test_accounts.md` — credentials + counting decision.",
        "- `role_test_results.md` — per-role login results.",
        "- `dashboard_data_audit.md` — persisted data backing every dashboard.",
        "- `defects_and_fixes.md` — defects found and remediation.",
        "- `tanzania_test_dataset.md` — dataset description.",
        "- `FINAL_QA_SUMMARY.md` — this file.",
        "",
    ]
    return "\n".join(lines)


def write_all(ctx) -> str:
    _write("role_test_accounts.md", _role_test_accounts())
    _write("role_test_results.md", _role_test_results(ctx))
    _write("dashboard_data_audit.md", _dashboard_data_audit())
    _write("defects_and_fixes.md", _defects_and_fixes(ctx))
    _write("tanzania_test_dataset.md", _dataset_doc())
    _write("FINAL_QA_SUMMARY.md", _final_summary(ctx))
    return str(REPORTS_DIR)
