# 3.4 ERD — Identity & Access

```mermaid
erDiagram
    users {
        bigint id PK
        uuid uid UK
        citext email UK
        text phone UK
        text password_hash
        text first_name
        text last_name
        text account_status
        boolean is_active
        boolean mfa_enabled
        bytea mfa_secret_encrypted
        text profile_photo_url
        timestamptz last_login_at
        timestamptz created_at
        timestamptz updated_at
        timestamptz deleted_at
    }
    roles {
        bigint id PK
        text code UK
        text name
        text description
        boolean is_privileged
        boolean is_medical
        boolean is_system
        timestamptz created_at
    }
    permissions {
        bigint id PK
        text code UK
        text module
        text resource
        text action
        boolean is_sensitive
        timestamptz created_at
    }
    role_permissions {
        bigint id PK
        bigint role_id FK
        bigint permission_id FK
        timestamptz created_at
    }
    user_roles {
        bigint id PK
        bigint user_id FK
        bigint role_id FK
        boolean is_active
        bigint granted_by FK
        timestamptz granted_at
        timestamptz revoked_at
    }
    user_permissions {
        bigint id PK
        bigint user_id FK
        bigint permission_id FK
        text effect
        bigint granted_by FK
        text reason
        timestamptz granted_at
        timestamptz revoked_at
    }
    verification_documents {
        bigint id PK
        bigint user_id FK
        text doc_type
        text file_url
        text status
        bigint reviewed_by FK
        timestamptz reviewed_at
        text rejection_reason
        timestamptz created_at
    }
    token_denylist {
        text jti PK
        bigint user_id FK
        timestamptz expires_at
        timestamptz revoked_at
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

    users ||--o{ user_roles : "1:*"
    users ||--o{ user_permissions : "1:*"
    roles ||--o{ user_roles : "1:*"
    roles ||--o{ role_permissions : "1:*"
    permissions ||--o{ role_permissions : "1:*"
    permissions ||--o{ user_permissions : "1:*"
    users ||--o{ verification_documents : "1:*"
    users ||--o| token_denylist : "jti per user"
    users ||--o{ security_events : "1:*"
    users ||--o{ users : "granted_by/reviewed_by"
```

Constraints:
- `roles.code`, `permissions.code` unique.
- `user_roles(user_id, role_id)` unique; `user_permissions(user_id, permission_id)` unique.
- `account_status` CHECK (ACTIVE, PENDING_VERIFICATION, SUSPENDED, DISABLED, DEACTIVATED).
- `effect` CHECK (ALLOW, DENY).
- Multi-role aggregation + SUP-only role assignment (Stage 3.3).