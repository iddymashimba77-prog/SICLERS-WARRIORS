# 3.4 ERD — Community & Communication

```mermaid
erDiagram
    community_posts {
        bigint id PK
        uuid uid UK
        bigint author_user_id FK
        text title
        text content
        text category
        text status
        bigint moderated_by FK
        timestamptz moderated_at
        text moderation_reason
        timestamptz created_at
        timestamptz updated_at
        timestamptz deleted_at
    }
    comments {
        bigint id PK
        bigint post_id FK
        bigint author_user_id FK
        text content
        text status
        timestamptz created_at
        timestamptz updated_at
    }
    reactions {
        bigint id PK
        bigint post_id FK
        bigint user_id FK
        text reaction_type
        timestamptz created_at
    }
    reports {
        bigint id PK
        bigint reporter_user_id FK
        text target_type
        bigint target_id
        text reason
        text status
        bigint reviewed_by FK
        text review_notes
        timestamptz created_at
        timestamptz updated_at
    }
    conversations {
        bigint id PK
        uuid uid UK
        text type
        bigint created_by FK
        text status
        timestamptz last_message_at
        timestamptz created_at
        timestamptz updated_at
    }
    conversation_participants {
        bigint id PK
        bigint conversation_id FK
        bigint user_id FK
        text role_in_chat
        text status
        bigint invited_by FK
        timestamptz joined_at
    }
    messages {
        bigint id PK
        uuid uid UK
        bigint conversation_id FK
        bigint sender_id FK
        text content
        text message_type
        text status
        timestamptz created_at
        timestamptz deleted_at
    }
    message_attachments {
        bigint id PK
        bigint message_id FK
        text file_url
        text content_type
        bigint size_bytes
        bigint uploaded_by FK
        timestamptz uploaded_at
    }
    education_categories {
        bigint id PK
        text code UK
        text name
        integer sort_order
    }
    educational_content {
        bigint id PK
        uuid uid UK
        bigint category_id FK
        text title
        text body
        bigint author_user_id FK
        text status
        bigint reviewed_by FK
        timestamptz reviewed_at
        text rejection_reason
        text cover_url
        timestamptz published_at
        timestamptz created_at
        timestamptz updated_at
    }

    users ||--o{ community_posts : "author"
    users ||--o{ reports : "reporter"
    community_posts ||--o{ comments : "1:*"
    community_posts ||--o{ reactions : "1:*"
    community_posts ||--o{ reports : "polymorphic target"
    users ||--o{ conversations : "creator"
    users ||--o{ conversation_participants : ""
    conversations ||--o{ conversation_participants : "1:*"
    conversations ||--o{ messages : "1:*"
    messages ||--o{ message_attachments : "1:*"
    education_categories ||--o{ educational_content : "1:*"
    users ||--o{ educational_content : "author"
```

Constraints & notes:
- `reactions(post_id, user_id, reaction_type)` unique; `conversation_participants(conversation_id, user_id)` unique.
- Doctor-patient chat requires active consent/authorized context; participant object-level checks at API layer (Stage 3.3 §17).
- Community content is separable from private medical records.