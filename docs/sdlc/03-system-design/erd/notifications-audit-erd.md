# 3.4 ERD — Notifications & Audit

```mermaid
erDiagram
    notifications {
        bigint id PK
        bigint recipient_user_id FK
        text type
        text channel
        text title
        text body
        text related_resource_type
        bigint related_resource_id
        text status
        text delivery_key UK
        timestamptz read_at
        timestamptz sent_at
        timestamptz created_at
    }
    notification_preferences {
        bigint id PK
        bigint user_id FK
        text category
        boolean enabled
        timestamptz updated_at
    }
    audit_logs {
        bigint id PK
        bigint actor_user_id FK
        text action_code
        text resource_type
        bigint resource_id
        text result
        text ip_address
        text user_agent
        uuid request_id
        jsonb details
        timestamptz created_at
    }
    security_events {
        bigint id PK
        bigint user_id FK
        text event_type
        text status
        text ip_address
        text user_agent
        jsonb detail
        timestamptz created_at
    }
    analytics_snapshots {
        bigint id PK
        text metric_key
        jsonb dimensions
        numeric value
        text granularity
        timestamptz measured_at
    }

    users ||--o{ notifications : "recipient"
    users ||--o{ notification_preferences : "1:*"
    users ||--o{ audit_logs : "actor"
    users ||--o{ security_events : "1:*"
```

Constraints & notes:
- `notification_preferences(user_id, category)` unique; `analytics_snapshots(metric_key, dimensions, granularity, measured_at)` unique.
- Audit logs append-only (no update/delete); no PHI in `details` (Stage 3.3 §22).
- `analytics_snapshots` store aggregates only — no duplicated sensitive/medical data (§19).
- Indexes: `audit_logs(resource_type, resource_id, created_at)`,
  `notifications(recipient_user_id, created_at)`.