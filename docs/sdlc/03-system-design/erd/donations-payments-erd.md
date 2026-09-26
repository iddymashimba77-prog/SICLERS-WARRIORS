# 3.4 ERD — Donations & Payments

```mermaid
erDiagram
    organizations {
        bigint id PK
        uuid uid UK
        text org_type
        text name
        text registration_number
        text contact_email
        boolean is_verified
        bigint verified_by FK
        timestamptz verified_at
        timestamptz created_at
        timestamptz updated_at
    }
    organization_members {
        bigint id PK
        bigint organization_id FK
        bigint user_id FK
        text member_role
        boolean is_active
        bigint granted_by FK
        timestamptz created_at
        timestamptz updated_at
    }
    campaigns {
        bigint id PK
        uuid uid UK
        bigint owner_user_id FK
        bigint organization_id FK
        text title
        text description
        numeric goal_amount
        numeric raised_amount
        char currency
        text status
        bigint verified_by FK
        timestamptz verified_at
        text rejection_reason
        timestamptz start_date
        timestamptz end_date
        timestamptz created_at
        timestamptz updated_at
        timestamptz deleted_at
    }
    donations {
        bigint id PK
        uuid uid UK
        bigint campaign_id FK
        bigint donor_user_id FK
        numeric amount
        char currency
        text status
        text transaction_ref UK
        text idempotency_key UK
        timestamptz created_at
        timestamptz updated_at
    }
    payment_transactions {
        bigint id PK
        bigint donation_id FK
        text provider
        text provider_ref UK
        text status
        numeric amount
        char currency
        jsonb payload
        integer attempt
        timestamptz created_at
        timestamptz updated_at
    }
    refunds {
        bigint id PK
        bigint donation_id FK
        bigint transaction_id FK
        numeric amount
        text reason
        bigint initiated_by FK
        bigint approved_by FK
        text status
        timestamptz created_at
        timestamptz updated_at
    }

    organizations ||--o{ organization_members : "1:*"
    users ||--o{ organization_members : "membership"
    users ||--o{ campaigns : "owner"
    organizations ||--o{ campaigns : "1:*"
    campaigns ||--o{ donations : "1:*"
    users ||--o{ donations : "donor"
    donations ||--o{ payment_transactions : "1:*"
    donations ||--o{ refunds : "1:*"
```

Constraints & notes:
- `goal_amount`, `amount` CHECK > 0; `status` CHECKs on campaigns/donations/txns/refunds.
- Payment success verified server-side (webhook + signature); no client-side trust (BR-008).
- `transaction_ref`, `idempotency_key`, `provider_ref` unique — safe duplicate webhooks (FR-PAY-004).
- Payload redacted: no PAN/token/card data in `payload` (privacy §25).