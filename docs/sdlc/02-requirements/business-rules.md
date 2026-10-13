# 2.5 Business Rules

Hizi ni kanuni za mfumo, sio features.

| ID | Rule |
|---|---|
| BR-001 | Only verified healthcare professionals can perform doctor-specific functions. |
| BR-002 | Medical records are private by default. |
| BR-003 | A doctor cannot access a patient's complete medical history merely because the doctor has an account. |
| BR-004 | Medical access must follow explicit authorization/consent rules. |
| BR-005 | Only verified blood requests may become publicly active. |
| BR-006 | Blood donor contact information must not be publicly exposed. |
| BR-007 | Fundraising campaigns must be verified before accepting public donations. |
| BR-008 | Payment confirmation must be verified by the backend/payment provider. |
| BR-009 | Emergency requests must be protected against spam and abuse. |
| BR-010 | AI must not autonomously diagnose patients. |
| BR-011 | AI must not autonomously prescribe or modify medication dosage. |
| BR-012 | Critical system activities must be auditable. |
| BR-013 | Professional verification grants identity confirmation only. It never grants a clinical privilege: prescribing stays with the DOCTOR role, and every other permission still comes from the role's own bundle plus consent. |
| BR-014 | A care-team role (psychologist, social support worker) may not author or alter a clinical record without an active patient consent scope, and a social support worker may never author a clinical record at all. |

## Kanuni zilizokubaliwa kwa AI / Safety

- AI output sio medical diagnosis (inahitihibitishwa kwenye UI).
- Emergency triage inaacha maamuzi ya klinikali kwa healthcare professionals.