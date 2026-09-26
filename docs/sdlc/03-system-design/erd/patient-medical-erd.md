# 3.4 ERD — Patient & Medical

```mermaid
erDiagram
    patients {
        bigint id PK
        bigint user_id FK
        date date_of_birth
        text gender
        text genotype
        date diagnosis_date
        text primary_diagnosis
        text emergency_contact_name
        text emergency_contact_phone
        text emergency_contact_relation
        text address_region
        text address_city
        text notes
        timestamptz created_at
        timestamptz updated_at
        timestamptz deleted_at
    }
    caregivers {
        bigint id PK
        bigint patient_id FK
        bigint user_id FK
        text relationship_type
        text status
        bigint invited_by FK
        timestamptz accepted_at
        timestamptz created_at
        timestamptz updated_at
    }
    patient_preferences {
        bigint id PK
        bigint patient_id FK
        text language
        text reminder_timezone
        text theme
        boolean share_blood_status
    }
    consents {
        bigint id PK
        uuid uid UK
        bigint patient_profile_id FK
        bigint granted_to_user_id FK
        bigint authorized_role_id FK
        text resource_type
        jsonb resource_ids
        jsonb permission_scope
        text purpose
        timestamptz start_date
        timestamptz expires_at
        text status
        bigint revoked_by FK
        timestamptz revoked_at
        timestamptz created_at
        timestamptz updated_at
    }
    record_categories {
        bigint id PK
        text code UK
        text name
        boolean is_confidential
    }
    clinical_encounters {
        bigint id PK
        uuid uid UK
        bigint patient_id FK
        bigint facility_id FK
        bigint doctor_id FK
        bigint staff_id FK
        text encounter_type
        timestamptz occurred_at
        text summary
        bigint created_by FK
        timestamptz created_at
    }
    medical_records {
        bigint id PK
        uuid uid UK
        bigint patient_id FK
        bigint category_id FK
        bigint encounter_id FK
        text title
        text description
        bigint facility_id FK
        bigint recorded_by FK
        timestamptz recorded_at
        text status
        boolean is_consent_visible
        timestamptz created_at
        timestamptz updated_at
        timestamptz deleted_at
    }
    medical_record_files {
        bigint id PK
        bigint record_id FK
        text file_url
        text file_name
        text content_type
        bigint size_bytes
        text checksum
        bigint uploaded_by FK
        timestamptz uploaded_at
    }
    medical_record_links {
        bigint id PK
        bigint record_id FK
        bigint granted_to_user_id FK
        jsonb scope
        timestamptz expires_at
        bigint granted_by_patient_id FK
        timestamptz granted_at
        timestamptz revoked_at
        bigint revoked_by FK
    }
    medications {
        bigint id PK
        uuid uid UK
        bigint patient_id FK
        text name
        text generic_name
        text strength
        text dosage
        text route
        text frequency
        date start_date
        date end_date
        bigint prescribed_by_id FK
        boolean is_active
        timestamptz created_at
        timestamptz updated_at
        timestamptz deleted_at
    }
    medication_schedules {
        bigint id PK
        bigint medication_id FK
        time time_of_day
        jsonb days_of_week
        text notes
    }
    medication_events {
        bigint id PK
        bigint schedule_id FK
        bigint patient_id FK
        text status
        timestamptz taken_at
        text note
        timestamptz created_at
    }
    symptom_types {
        bigint id PK
        text code UK
        text name
        boolean is_pain_related
    }
    symptoms {
        bigint id PK
        uuid uid UK
        bigint patient_id FK
        bigint symptom_type_id FK
        smallint pain_level
        jsonb triggers
        integer duration_minutes
        text notes
        timestamptz recorded_at
        timestamptz created_at
    }
    health_timeline {
        bigint id PK
        bigint patient_id FK
        text event_type
        bigint event_id
        timestamptz occurred_at
        text summary
        jsonb payload
    }
    appointments {
        bigint id PK
        uuid uid UK
        bigint patient_id FK
        bigint doctor_id FK
        bigint facility_id FK
        timestamptz scheduled_time
        smallint duration_minutes
        text type
        text status
        text cancel_reason
        bigint created_by FK
        timestamptz created_at
        timestamptz updated_at
    }

    users ||--o| patients : "1:1"
    patients ||--o{ caregivers : "1:*"
    patients ||--o| patient_preferences : "1:1"
    patients ||--o{ consents : "1:*"
    patients ||--o{ clinical_encounters : "1:*"
    patients ||--o{ medical_records : "1:*"
    patients ||--o{ medications : "1:*"
    patients ||--o{ symptoms : "1:*"
    patients ||--o{ health_timeline : "1:*"
    patients ||--o{ appointments : "1:*"
    record_categories ||--o{ medical_records : ""
    clinical_encounters ||--o{ medical_records : ""
    medical_records ||--o{ medical_record_files : ""
    medical_records ||--o{ medical_record_links : ""
    medications ||--o{ medication_schedules : ""
    medication_schedules ||--o{ medication_events : ""
    symptom_types ||--o{ symptoms : ""
```

Constraints & notes:
- `caregivers(patient_id, user_id)` unique; CAREGIVER role alone grants no access — `consents` authorize (Stage 3.3 §10/§15).
- `consents.status` CHECK (DRAFT, ACTIVE, REVOKED, EXPIRED); `permission_scope` = array of permission codes.
- `pain_level` CHECK 0..10; appointments type/status CHECK.
- Medical data is Highly Sensitive (consent-gated, §25).