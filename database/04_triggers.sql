-- Small audit/maintenance triggers. Business decisions remain in PKG_LEDGERLENS.
SET DEFINE OFF

CREATE OR REPLACE TRIGGER trg_accounts_updated_at
BEFORE UPDATE ON accounts
FOR EACH ROW
BEGIN
    :NEW.updated_at := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER trg_transfers_status_audit
AFTER UPDATE OF status ON transfers
FOR EACH ROW
WHEN (OLD.status <> NEW.status)
BEGIN
    INSERT INTO audit_log (transfer_id, action, old_status, new_status, details)
    VALUES (:NEW.transfer_id, 'STATUS_CHANGED', :OLD.status, :NEW.status,
            'Transfer status changed by package operation.');
END;
/

SHOW ERRORS TRIGGER trg_accounts_updated_at
SHOW ERRORS TRIGGER trg_transfers_status_audit
PROMPT Triggers compiled if SHOW ERRORS reports no errors.
