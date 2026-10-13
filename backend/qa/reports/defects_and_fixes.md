# Defects & fixes — SWQA-TZ-2026

## Findings

1. **Notification type mismatch (fixed).** The canonical type is `APPOINTMENT` (not `APPOINTMENT_REMINDER`). Updated `notifications/reminders.py` and `appointments/tests.py` to use the canonical enum.

## Seeding defects found and fixed during this run
1. `ClinicAppointment.created_by` is `NOT NULL` — appointments now set the patient as booker.
2. `ClinicAppointment` seeding produced a null `scheduled_at`; replaced with a real computed datetime.
3. `EmergencyRequest.patient` / `EmergencyAccessGrant.patient` reference `User`, not `Patient` — corrected.
4. `relationships` phase iterated a generator of querysets — fixed to a materialised `Patient` list.
5. Shared PBKDF2 hashing per account caused a >300s timeout; hashing is now computed once and reused for all accounts.
