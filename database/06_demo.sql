-- Reproducible short demo. This script commits its two displayed example transfers.
SET SERVEROUTPUT ON

DECLARE
    l_from_id NUMBER;
    l_to_id NUMBER;
    l_transfer_id NUMBER;
    l_reference VARCHAR2(40);
    l_status VARCHAR2(24);
    l_risk CHAR(1);
    l_error VARCHAR2(1000);
BEGIN
    SELECT account_id INTO l_from_id FROM accounts WHERE account_number = 'LL-ACC-1001';
    SELECT account_id INTO l_to_id FROM accounts WHERE account_number = 'LL-ACC-1002';

    pkg_ledgerlens.create_transfer(l_from_id, l_to_id, 1000.00,
        l_transfer_id, l_reference, l_status, l_risk, l_error);
    DBMS_OUTPUT.PUT_LINE('Normal transfer: ' || l_reference || ' | ' || l_status ||
        CASE WHEN l_error IS NOT NULL THEN ' | ' || l_error END);

    pkg_ledgerlens.create_transfer(l_from_id, l_to_id, 60000.00,
        l_transfer_id, l_reference, l_status, l_risk, l_error);
    DBMS_OUTPUT.PUT_LINE('High-value transfer: ' || l_reference || ' | ' || l_status ||
        ' | risk=' || l_risk || CASE WHEN l_error IS NOT NULL THEN ' | ' || l_error END);

    COMMIT;
END;
/

@@05_reports.sql
