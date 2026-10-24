-- Fictional, deterministic classroom data. Run after 01_schema.sql.
SET DEFINE OFF
SET SERVEROUTPUT ON

INSERT INTO customers (full_name, email) VALUES ('Aarav Mehta', 'aarav.mehta@example.test');
INSERT INTO customers (full_name, email) VALUES ('Diya Rao', 'diya.rao@example.test');
INSERT INTO customers (full_name, email) VALUES ('Kabir Shah', 'kabir.shah@example.test');
INSERT INTO customers (full_name, email) VALUES ('Mira Nair', 'mira.nair@example.test');

INSERT INTO accounts (customer_id, account_number, account_type, balance, account_status)
SELECT customer_id, 'LL-ACC-1001', 'SAVINGS', 250000.00, 'ACTIVE' FROM customers WHERE email = 'aarav.mehta@example.test';
INSERT INTO accounts (customer_id, account_number, account_type, balance, account_status)
SELECT customer_id, 'LL-ACC-1002', 'CURRENT', 40000.00, 'ACTIVE' FROM customers WHERE email = 'diya.rao@example.test';
INSERT INTO accounts (customer_id, account_number, account_type, balance, account_status)
SELECT customer_id, 'LL-ACC-1003', 'SAVINGS', 125000.00, 'ACTIVE' FROM customers WHERE email = 'kabir.shah@example.test';
INSERT INTO accounts (customer_id, account_number, account_type, balance, account_status)
SELECT customer_id, 'LL-ACC-1004', 'CURRENT', 5000.00, 'ACTIVE' FROM customers WHERE email = 'mira.nair@example.test';
INSERT INTO accounts (customer_id, account_number, account_type, balance, account_status)
SELECT customer_id, 'LL-ACC-1005', 'SAVINGS', 75000.00, 'INACTIVE' FROM customers WHERE email = 'aarav.mehta@example.test';

INSERT INTO system_config (config_key, config_value, description)
VALUES ('HIGH_VALUE_THRESHOLD', '50000.00', 'Transfers at or above this amount are flagged for review. Example value only.');
INSERT INTO system_config (config_key, config_value, description)
VALUES ('TRANSFER_MODE', 'FLAG_AND_COMPLETE', 'Allowed values: FLAG_AND_COMPLETE or HOLD_FOR_REVIEW.');
INSERT INTO system_config (config_key, config_value, description)
VALUES ('MAX_TRANSFER_AMOUNT', '250000.00', 'Educational per-transfer limit used by validation.');

-- The schema owner is the initial operator. Add additional operator usernames explicitly.
INSERT INTO system_operators (username)
VALUES (UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER')));
INSERT INTO system_reviewers (username)
VALUES (UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER')));

COMMIT;
PROMPT Seed data installed. Fictional account numbers are LL-ACC-1001 through LL-ACC-1005.
