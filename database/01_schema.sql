-- LedgerLens schema for Oracle Database 19c or newer.
-- Run once in a new, dedicated schema. This script intentionally does not drop objects.
SET DEFINE OFF
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

CREATE TABLE customers (
    customer_id NUMBER GENERATED ALWAYS AS IDENTITY,
    full_name   VARCHAR2(120) NOT NULL,
    email       VARCHAR2(254) NOT NULL,
    created_at  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_customers PRIMARY KEY (customer_id),
    CONSTRAINT uq_customers_email UNIQUE (email)
);

CREATE TABLE accounts (
    account_id     NUMBER GENERATED ALWAYS AS IDENTITY,
    customer_id    NUMBER NOT NULL,
    account_number VARCHAR2(24) NOT NULL,
    account_type   VARCHAR2(16) NOT NULL,
    balance        NUMBER(18,2) DEFAULT 0 NOT NULL,
    account_status VARCHAR2(12) DEFAULT 'ACTIVE' NOT NULL,
    created_at     TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at     TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_accounts PRIMARY KEY (account_id),
    CONSTRAINT fk_accounts_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT uq_accounts_number UNIQUE (account_number),
    CONSTRAINT ck_accounts_type CHECK (account_type IN ('SAVINGS', 'CURRENT')),
    CONSTRAINT ck_accounts_balance CHECK (balance >= 0),
    CONSTRAINT ck_accounts_status CHECK (account_status IN ('ACTIVE', 'INACTIVE', 'CLOSED'))
);

CREATE TABLE system_config (
    config_key   VARCHAR2(64) NOT NULL,
    config_value VARCHAR2(100) NOT NULL,
    description  VARCHAR2(300) NOT NULL,
    updated_at   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_system_config PRIMARY KEY (config_key)
);

CREATE TABLE system_operators (
    username    VARCHAR2(128) NOT NULL,
    created_at  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_system_operators PRIMARY KEY (username)
);

CREATE TABLE system_reviewers (
    username    VARCHAR2(128) NOT NULL,
    created_at  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_system_reviewers PRIMARY KEY (username)
);

CREATE TABLE config_audit (
    config_audit_id NUMBER GENERATED ALWAYS AS IDENTITY,
    config_key      VARCHAR2(64) NOT NULL,
    old_value       VARCHAR2(100),
    new_value       VARCHAR2(100) NOT NULL,
    changed_by      VARCHAR2(128) NOT NULL,
    changed_at      TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_config_audit PRIMARY KEY (config_audit_id),
    CONSTRAINT fk_config_audit_key FOREIGN KEY (config_key) REFERENCES system_config(config_key)
);

CREATE TABLE transfers (
    transfer_id      NUMBER GENERATED ALWAYS AS IDENTITY,
    reference_number VARCHAR2(40) NOT NULL,
    from_account_id  NUMBER NOT NULL,
    to_account_id    NUMBER NOT NULL,
    amount           NUMBER(18,2) NOT NULL,
    status            VARCHAR2(24) DEFAULT 'PENDING' NOT NULL,
    risk_flag         CHAR(1) DEFAULT 'N' NOT NULL,
    risk_reason       VARCHAR2(500),
    created_at        TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    completed_at      TIMESTAMP,
    CONSTRAINT pk_transfers PRIMARY KEY (transfer_id),
    CONSTRAINT uq_transfers_reference UNIQUE (reference_number),
    CONSTRAINT fk_transfers_from FOREIGN KEY (from_account_id) REFERENCES accounts(account_id),
    CONSTRAINT fk_transfers_to FOREIGN KEY (to_account_id) REFERENCES accounts(account_id),
    CONSTRAINT ck_transfers_amount CHECK (amount > 0),
    CONSTRAINT ck_transfers_status CHECK (status IN ('PENDING', 'COMPLETED', 'HELD_FOR_REVIEW', 'FAILED', 'REJECTED')),
    CONSTRAINT ck_transfers_risk_flag CHECK (risk_flag IN ('Y', 'N')),
    CONSTRAINT ck_transfers_different_accounts CHECK (from_account_id <> to_account_id)
);

CREATE TABLE audit_log (
    audit_id   NUMBER GENERATED ALWAYS AS IDENTITY,
    transfer_id NUMBER NOT NULL,
    action     VARCHAR2(40) NOT NULL,
    old_status VARCHAR2(24),
    new_status VARCHAR2(24),
    details    VARCHAR2(1000),
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_audit_log PRIMARY KEY (audit_id),
    CONSTRAINT fk_audit_transfer FOREIGN KEY (transfer_id) REFERENCES transfers(transfer_id)
);

CREATE TABLE review_queue (
    review_id      NUMBER GENERATED ALWAYS AS IDENTITY,
    transfer_id    NUMBER NOT NULL,
    reason         VARCHAR2(500) NOT NULL,
    review_status  VARCHAR2(12) DEFAULT 'PENDING' NOT NULL,
    reviewer_notes VARCHAR2(1000),
    created_at     TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    reviewed_at    TIMESTAMP,
    CONSTRAINT pk_review_queue PRIMARY KEY (review_id),
    CONSTRAINT fk_review_transfer FOREIGN KEY (transfer_id) REFERENCES transfers(transfer_id),
    CONSTRAINT ck_review_status CHECK (review_status IN ('PENDING', 'APPROVED', 'REJECTED'))
);

CREATE INDEX ix_accounts_customer ON accounts(customer_id);
CREATE INDEX ix_transfers_created ON transfers(created_at);
CREATE INDEX ix_transfers_status ON transfers(status);
CREATE INDEX ix_transfers_from_account ON transfers(from_account_id);
CREATE INDEX ix_transfers_to_account ON transfers(to_account_id);
CREATE INDEX ix_audit_transfer_time ON audit_log(transfer_id, created_at);
CREATE INDEX ix_review_status_time ON review_queue(review_status, created_at);
CREATE INDEX ix_review_transfer ON review_queue(transfer_id, review_status, created_at);
-- A transfer can have historical reviews but at most one pending queue entry.
CREATE UNIQUE INDEX uq_review_one_pending ON review_queue
    (CASE WHEN review_status = 'PENDING' THEN transfer_id ELSE NULL END);

PROMPT LedgerLens schema created. Continue with 02_seed_data.sql.
