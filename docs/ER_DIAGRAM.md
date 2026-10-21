# LedgerLens ER Diagram

```mermaid
erDiagram
    CUSTOMERS ||--o{ ACCOUNTS : owns
    ACCOUNTS ||--o{ TRANSFERS : sends
    ACCOUNTS ||--o{ TRANSFERS : receives
    TRANSFERS ||--o{ AUDIT_LOG : records
    TRANSFERS ||--o{ REVIEW_QUEUE : reviewed_in
    SYSTEM_CONFIG ||--o{ CONFIG_AUDIT : changes

    CUSTOMERS {
        NUMBER customer_id PK
        VARCHAR2 full_name
        VARCHAR2 email UK
        TIMESTAMP created_at
    }
    ACCOUNTS {
        NUMBER account_id PK
        NUMBER customer_id FK
        VARCHAR2 account_number UK
        VARCHAR2 account_type
        NUMBER balance
        VARCHAR2 account_status
        TIMESTAMP created_at
        TIMESTAMP updated_at
    }
    TRANSFERS {
        NUMBER transfer_id PK
        VARCHAR2 reference_number UK
        NUMBER from_account_id FK
        NUMBER to_account_id FK
        NUMBER amount
        VARCHAR2 status
        CHAR risk_flag
        VARCHAR2 risk_reason
        TIMESTAMP created_at
        TIMESTAMP completed_at
    }
    AUDIT_LOG {
        NUMBER audit_id PK
        NUMBER transfer_id FK
        VARCHAR2 action
        VARCHAR2 old_status
        VARCHAR2 new_status
        VARCHAR2 details
        TIMESTAMP created_at
    }
    REVIEW_QUEUE {
        NUMBER review_id PK
        NUMBER transfer_id FK
        VARCHAR2 reason
        VARCHAR2 review_status
        VARCHAR2 reviewer_notes
        TIMESTAMP created_at
        TIMESTAMP reviewed_at
    }
    SYSTEM_CONFIG {
        VARCHAR2 config_key PK
        VARCHAR2 config_value
        VARCHAR2 description
        TIMESTAMP updated_at
    }
    CONFIG_AUDIT {
        NUMBER config_audit_id PK
        VARCHAR2 config_key FK
        VARCHAR2 old_value
        VARCHAR2 new_value
        VARCHAR2 changed_by
        TIMESTAMP changed_at
    }
    SYSTEM_OPERATORS {
        VARCHAR2 username PK
        TIMESTAMP created_at
    }
    SYSTEM_REVIEWERS {
        VARCHAR2 username PK
        TIMESTAMP created_at
    }
```

The ER model uses two named relationships from `ACCOUNTS` to `TRANSFERS` because each transfer references one source and one destination account. `SYSTEM_OPERATORS` controls package access to threshold updates and is not a customer entity.
