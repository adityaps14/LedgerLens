-- Run individual sections with F5 / Run Script in SQL Developer or execute this file in SQLcl.
SET PAGESIZE 100
SET LINESIZE 220
SET FEEDBACK ON

PROMPT === All transfers with account and customer details ===
SELECT t.transfer_id, t.reference_number, fa.account_number AS from_account,
       fc.full_name AS sender, ta.account_number AS to_account, tc.full_name AS receiver,
       t.amount, t.status, t.risk_flag, t.risk_reason, t.created_at, t.completed_at
  FROM transfers t
  JOIN accounts fa ON fa.account_id = t.from_account_id
  JOIN customers fc ON fc.customer_id = fa.customer_id
  JOIN accounts ta ON ta.account_id = t.to_account_id
  JOIN customers tc ON tc.customer_id = ta.customer_id
 ORDER BY t.created_at DESC;

PROMPT === Current account balances ===
SELECT a.account_number, c.full_name AS account_holder, a.account_type,
       a.balance, a.account_status, a.updated_at
  FROM accounts a JOIN customers c ON c.customer_id = a.customer_id
 ORDER BY a.account_number;

PROMPT === High-value transfers and reasons ===
SELECT transfer_id, reference_number, amount, status, risk_reason, created_at
  FROM transfers WHERE risk_flag = 'Y' ORDER BY created_at DESC;

PROMPT === Pending review queue ===
SELECT r.review_id, t.transfer_id, t.reference_number, t.amount, r.reason, r.created_at
  FROM review_queue r JOIN transfers t ON t.transfer_id = r.transfer_id
 WHERE r.review_status = 'PENDING' ORDER BY r.created_at;

PROMPT === Audit history for a transfer (replace 1 with the transfer ID) ===
SELECT audit_id, action, old_status, new_status, details, created_at
  FROM audit_log WHERE transfer_id = 1 ORDER BY created_at, audit_id;

PROMPT === Daily transfer count and total requested value ===
SELECT TRUNC(created_at) AS transfer_day, COUNT(*) AS transfer_count,
       SUM(amount) AS total_transfer_value
  FROM transfers GROUP BY TRUNC(created_at) ORDER BY transfer_day DESC;

PROMPT === Transfer counts grouped by status ===
SELECT status, COUNT(*) AS transfer_count, SUM(amount) AS total_amount
  FROM transfers GROUP BY status ORDER BY status;

PROMPT === Failed and rejected transfers ===
SELECT transfer_id, reference_number, from_account_id, to_account_id,
       amount, status, risk_reason, created_at
  FROM transfers WHERE status IN ('FAILED', 'REJECTED') ORDER BY created_at DESC;

PROMPT === Current configuration values ===
SELECT config_key, config_value, description, updated_at
  FROM system_config ORDER BY config_key;

PROMPT === Threshold change history ===
SELECT config_audit_id, config_key, old_value, new_value, changed_by, changed_at
  FROM config_audit ORDER BY changed_at DESC;
