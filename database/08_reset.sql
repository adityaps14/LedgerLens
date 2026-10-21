-- DANGEROUS BY DESIGN: clears all transfer/review/audit history and restores seed balances/configuration.
-- Run only in the dedicated classroom schema after backing up anything you need.
SET DEFINE ON
SET SERVEROUTPUT ON
ACCEPT confirm_reset CHAR PROMPT 'Type YES to clear LedgerLens demo history and restore seed state: '
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

DECLARE
    l_confirm VARCHAR2(10) := UPPER(TRIM('&confirm_reset'));
BEGIN
    IF l_confirm <> 'YES' THEN
        DBMS_OUTPUT.PUT_LINE('Reset cancelled. No rows were changed.');
    ELSE
        DELETE FROM review_queue;
        DELETE FROM audit_log;
        DELETE FROM transfers;
        DELETE FROM config_audit;
        UPDATE accounts SET balance = CASE account_number
            WHEN 'LL-ACC-1001' THEN 250000.00
            WHEN 'LL-ACC-1002' THEN 40000.00
            WHEN 'LL-ACC-1003' THEN 125000.00
            WHEN 'LL-ACC-1004' THEN 5000.00
            WHEN 'LL-ACC-1005' THEN 75000.00
        END,
        account_status = CASE WHEN account_number = 'LL-ACC-1005' THEN 'INACTIVE' ELSE 'ACTIVE' END
        WHERE account_number IN ('LL-ACC-1001','LL-ACC-1002','LL-ACC-1003','LL-ACC-1004','LL-ACC-1005');
        UPDATE system_config SET config_value = '50000.00', updated_at = SYSTIMESTAMP
         WHERE config_key = 'HIGH_VALUE_THRESHOLD';
        UPDATE system_config SET config_value = 'FLAG_AND_COMPLETE', updated_at = SYSTIMESTAMP
         WHERE config_key = 'TRANSFER_MODE';
        UPDATE system_config SET config_value = '250000.00', updated_at = SYSTIMESTAMP
         WHERE config_key = 'MAX_TRANSFER_AMOUNT';
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('LedgerLens demo data reset to the documented seed state.');
    END IF;
END;
/
