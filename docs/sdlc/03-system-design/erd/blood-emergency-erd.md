# 3.4 ERD — Blood & Emergency

```mermaid
erDiagram
    facilities {
        bigint id PK
        uuid uid UK
        text name
        text facility_type
        text region
        text city
        text address
        text registration_number
        boolean is_verified
        bigint verified_by FK
        timestamptz verified_at
        timestamptz created_at
        timestamptz updated_at
    }
    blood_donors {
        bigint id PK
        bigint user_id FK
        text blood_group
        text region
        text city
        boolean is_available
        date last_donation_date
        integer donation_count
        boolean is_verified
        bigint verified_by FK
        timestamptz verified_at
        timestamptz created_at
        timestamptz updated_at
    }
    blood_requests {
        bigint id PK
        uuid uid UK
        bigint patient_id FK
        bigint created_by FK
        text blood_group_needed
        smallint units
        text urgency
        bigint facility_id FK
        text reason
        jsonb location
        text status
        bigint verified_by FK
        timestamptz verified_at
        text rejection_reason
        timestamptz created_at
        timestamptz updated_at
    }
    blood_matches {
        bigint id PK
        bigint request_id FK
        bigint donor_id FK
        numeric match_score
        jsonb match_reason
        text status
        timestamptz notified_at
        timestamptz responded_at
        timestamptz fulfilled_at
        timestamptz created_at
    }
    blood_donation_events {
        bigint id PK
        bigint donor_id FK
        bigint request_id FK
        bigint facility_id FK
        smallint units
        timestamptz donated_at
        text outcome
        text donation_serial UK
        bigint recorded_by FK
        timestamptz created_at
    }
    emergency_requests {
        bigint id PK
        uuid uid UK
        bigint requester_user_id FK
        bigint patient_profile_id FK
        text severity
        text type
        jsonb location
        text description
        text status
        boolean rate_limit_ok
        boolean phone_verified
        timestamptz escalated_at
        bigint resolved_by FK
        timestamptz resolved_at
        timestamptz created_at
        timestamptz updated_at
    }
    emergency_responders {
        bigint id PK
        bigint request_id FK
        bigint responder_user_id FK
        text responder_role
        text status
        timestamptz notified_at
        timestamptz acknowledged_at
        timestamptz arrived_at
        timestamptz completed_at
        timestamptz updated_at
    }
    emergency_access_grants {
        bigint id PK
        uuid uid UK
        bigint request_id FK
        bigint patient_profile_id FK
        bigint grantee_user_id FK
        jsonb scope
        text reason
        bigint authorized_by FK
        timestamptz starts_at
        timestamptz expires_at
        text status
        bigint revoked_by FK
        timestamptz revoked_at
        timestamptz created_at
    }

    users ||--o| blood_donors : "1:1"
    users ||--o| facilities : "operator"
    patients ||--o{ blood_requests : "1:*"
    facilities ||--o{ blood_requests : "1:*"
    blood_requests ||--o{ blood_matches : "1:*"
    blood_donors ||--o{ blood_matches : "1:*"
    blood_donors ||--o{ blood_donation_events : "1:*"
    blood_requests ||--o{ blood_donation_events : "fulfillment"
    users ||--o{ emergency_requests : "requester"
    patients ||--o{ emergency_requests : "1:*"
    emergency_requests ||--o{ emergency_responders : "1:*"
    emergency_requests ||--o{ emergency_access_grants : "1:*"
```

Constraints & notes:
- `blood_group` CHECK (A+, A-, B+, B-, AB+, AB-, O+, O-); request `urgency` CHECK (NORMAL, URGENT, CRITICAL).
- Requests carry **no donor PII**; donor contact released only through accepted/fulfilled workflow at a facility (BR-006).
- `emergency_access_grants` bounded (default 24h), auto-expiry, audited — no bypass-all rule (Stage 3.3 §16).