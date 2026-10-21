-- Oracle SQL/PLSQL test suite. Run after schema, seed, package, and trigger scripts.
-- Every case rolls back to its savepoint. IDs are looked up by the deterministic account numbers.
SET SERVEROUTPUT ON
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

DECLARE
    l_passes PLS_INTEGER := 0;
    l_failures PLS_INTEGER := 0;
    l_from_id NUMBER;
    l_to_id NUMBER;
    l_inactive_id NUMBER;
    l_transfer_id NUMBER;
    l_reference VARCHAR2(40);
    l_status VARCHAR2(24);
    l_risk CHAR(1);
    l_error VARCHAR2(1000);
    l_before_from NUMBER;
    l_before_to NUMBER;
    l_after_from NUMBER;
    l_after_to NUMBER;
    l_count NUMBER;

    PROCEDURE report_case(p_name VARCHAR2, p_pass BOOLEAN, p_detail VARCHAR2) IS
    BEGIN
        IF p_pass THEN
            l_passes := l_passes + 1;
            DBMS_OUTPUT.PUT_LINE('PASS - ' || p_name || ' - ' || p_detail);
        ELSE
            l_failures := l_failures + 1;
            DBMS_OUTPUT.PUT_LINE('FAIL - ' || p_name || ' - ' || p_detail);
        END IF;
    END;

    PROCEDURE require_true(p_condition BOOLEAN, p_message VARCHAR2) IS
    BEGIN
        -- A NULL condition must fail too; PL/SQL IF treats NULL as not TRUE.
        IF p_condition THEN
            NULL;
        ELSE
            RAISE_APPLICATION_ERROR(-20990, p_message);
        END IF;
    END;

    FUNCTION balance_for(p_account_number VARCHAR2) RETURN NUMBER IS
        l_balance NUMBER;
    BEGIN
        SELECT balance INTO l_balance FROM accounts WHERE account_number = p_account_number;
        RETURN l_balance;
    END;

    PROCEDURE create_example(p_amount NUMBER, p_from NUMBER, p_to NUMBER) IS
    BEGIN
        pkg_ledgerlens.create_transfer(p_from, p_to, p_amount,
            l_transfer_id, l_reference, l_status, l_risk, l_error);
    END;
BEGIN
    SELECT account_id INTO l_from_id FROM accounts WHERE account_number = 'LL-ACC-1001';
    SELECT account_id INTO l_to_id FROM accounts WHERE account_number = 'LL-ACC-1002';
    SELECT account_id INTO l_inactive_id FROM accounts WHERE account_number = 'LL-ACC-1005';
    SAVEPOINT test01;
    BEGIN
        l_before_from := balance_for('LL-ACC-1001'); l_before_to := balance_for('LL-ACC-1002');
        create_example(1000, l_from_id, l_to_id);
        require_true(l_status = 'COMPLETED' AND l_risk = 'N', 'Expected a completed, unflagged transfer. ' || NVL(l_error, ''));
        require_true(balance_for('LL-ACC-1001') = l_before_from - 1000 AND balance_for('LL-ACC-1002') = l_before_to + 1000,
                     'Expected source debit and recipient credit of 1000.');
        ROLLBACK TO test01; report_case('Successful normal transfer', TRUE, 'Balances moved atomically by 1000.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test01; report_case('Successful normal transfer', FALSE, SQLERRM);
    END;

    SAVEPOINT test02;
    BEGIN
        create_example(60000, l_from_id, l_to_id);
        require_true(l_status = 'COMPLETED' AND l_risk = 'Y', 'Expected a completed transfer with risk flag Y.');
        SELECT COUNT(*) INTO l_count FROM review_queue WHERE transfer_id = l_transfer_id AND review_status = 'PENDING';
        require_true(l_count = 1, 'Expected one pending review item.');
        ROLLBACK TO test02; report_case('High-value transfer is flagged', TRUE, '60000 meets the seeded threshold and creates one review item.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test02; report_case('High-value transfer is flagged', FALSE, SQLERRM);
    END;

    SAVEPOINT test02a;
    BEGIN
        create_example(50000, l_from_id, l_to_id);
        require_true(l_status = 'COMPLETED' AND l_risk = 'Y', 'An amount equal to the threshold must be flagged.');
        ROLLBACK TO test02a; report_case('Threshold equality is high-value', TRUE, 'Amount equal to 50000.00 was flagged.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test02a; report_case('Threshold equality is high-value', FALSE, SQLERRM);
    END;

    SAVEPOINT test02b;
    BEGIN
        create_example(60000, l_from_id, l_to_id);
        l_after_from := balance_for('LL-ACC-1001'); l_after_to := balance_for('LL-ACC-1002');
        pkg_ledgerlens.review_transfer(l_transfer_id, 'REJECTED', 'Test Reviewer',
            'Post-execution disposition test.', l_status, l_error);
        require_true(l_status = 'COMPLETED', 'Review rejection must not rewrite a completed transfer status.');
        require_true(balance_for('LL-ACC-1001') = l_after_from AND balance_for('LL-ACC-1002') = l_after_to,
                     'Post-execution review changed balances.');
        SELECT COUNT(*) INTO l_count FROM review_queue
         WHERE transfer_id = l_transfer_id AND review_status = 'REJECTED';
        require_true(l_count = 1, 'Expected completed-transfer review disposition to be recorded.');
        ROLLBACK TO test02b; report_case('Completed high-value review cannot reverse funds', TRUE, 'Queue rejection was recorded without changing completed state or balances.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test02b; report_case('Completed high-value review cannot reverse funds', FALSE, SQLERRM);
    END;

    SAVEPOINT test03;
    BEGIN
        pkg_ledgerlens.set_high_value_threshold(70000);
        create_example(60000, l_from_id, l_to_id);
        require_true(l_status = 'COMPLETED' AND l_risk = 'N', '60000 should be below the temporary 70000 threshold.');
        ROLLBACK TO test03; report_case('Configurable threshold changes classification', TRUE, 'Threshold update changes classification and is rolled back.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test03; report_case('Configurable threshold changes classification', FALSE, SQLERRM);
    END;

    SAVEPOINT test04;
    BEGIN
        l_before_from := balance_for('LL-ACC-1001');
        create_example(999999, l_from_id, l_to_id);
        require_true(l_status = 'FAILED' AND l_error LIKE '%Insufficient%', 'Expected an insufficient-balance failure. ' || NVL(l_error, ''));
        require_true(balance_for('LL-ACC-1001') = l_before_from, 'Source balance changed after failed validation.');
        ROLLBACK TO test04; report_case('Insufficient funds preserve balances', TRUE, 'Transfer failed and source balance stayed unchanged.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test04; report_case('Insufficient funds preserve balances', FALSE, SQLERRM);
    END;

    SAVEPOINT test05;
    BEGIN
        create_example(0, l_from_id, l_to_id);
        require_true(l_status = 'FAILED' AND l_error LIKE '%greater than zero%', 'Zero amount was not rejected clearly.');
        create_example(-1, l_from_id, l_to_id);
        require_true(l_status = 'FAILED' AND l_error LIKE '%greater than zero%', 'Negative amount was not rejected clearly.');
        ROLLBACK TO test05; report_case('Zero and negative amounts are rejected', TRUE, 'Both invalid values returned FAILED.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test05; report_case('Zero and negative amounts are rejected', FALSE, SQLERRM);
    END;

    SAVEPOINT test06;
    BEGIN
        create_example(100, l_from_id, l_from_id);
        require_true(l_status = 'FAILED' AND l_error LIKE '%different%', 'Same-account transfer was not rejected clearly.');
        ROLLBACK TO test06; report_case('Same-account transfer is rejected', TRUE, 'No transfer was created for identical accounts.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test06; report_case('Same-account transfer is rejected', FALSE, SQLERRM);
    END;

    SAVEPOINT test07;
    BEGIN
        create_example(100, -999, l_to_id);
        require_true(l_status = 'FAILED' AND l_error LIKE '%does not exist%', 'Unknown account ID was not handled.');
        ROLLBACK TO test07; report_case('Invalid account IDs are handled', TRUE, 'No transfer was created for an unknown account.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test07; report_case('Invalid account IDs are handled', FALSE, SQLERRM);
    END;

    SAVEPOINT test08;
    BEGIN
        create_example(100, l_inactive_id, l_to_id);
        require_true(l_status = 'FAILED' AND l_error LIKE '%ACTIVE%', 'Inactive source account was not rejected.');
        ROLLBACK TO test08; report_case('Inactive accounts cannot transfer', TRUE, 'Inactive source was rejected.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test08; report_case('Inactive accounts cannot transfer', FALSE, SQLERRM);
    END;

    SAVEPOINT test09;
    BEGIN
        UPDATE system_config SET config_value = 'HOLD_FOR_REVIEW' WHERE config_key = 'TRANSFER_MODE';
        l_before_from := balance_for('LL-ACC-1001'); l_before_to := balance_for('LL-ACC-1002');
        create_example(60000, l_from_id, l_to_id);
        require_true(l_status = 'HELD_FOR_REVIEW' AND l_risk = 'Y', 'Expected held status and risk flag.');
        require_true(balance_for('LL-ACC-1001') = l_before_from AND balance_for('LL-ACC-1002') = l_before_to,
                     'Balances changed before review approval.');
        ROLLBACK TO test09; report_case('Held transfers do not change balances', TRUE, 'High-value request is queued with unchanged balances.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test09; report_case('Held transfers do not change balances', FALSE, SQLERRM);
    END;

    SAVEPOINT test10;
    BEGIN
        UPDATE system_config SET config_value = 'HOLD_FOR_REVIEW' WHERE config_key = 'TRANSFER_MODE';
        l_before_from := balance_for('LL-ACC-1001'); l_before_to := balance_for('LL-ACC-1002');
        create_example(60000, l_from_id, l_to_id);
        pkg_ledgerlens.review_transfer(l_transfer_id, 'APPROVED', 'Test Reviewer', 'Approved in test.', l_status, l_error);
        require_true(l_status = 'COMPLETED', 'Approval did not complete the held transfer. ' || NVL(l_error, ''));
        l_after_from := balance_for('LL-ACC-1001'); l_after_to := balance_for('LL-ACC-1002');
        require_true(l_after_from = l_before_from - 60000 AND l_after_to = l_before_to + 60000, 'Approval moved the wrong balances.');
        pkg_ledgerlens.process_transfer(l_transfer_id, l_status, l_error);
        require_true(balance_for('LL-ACC-1001') = l_after_from AND balance_for('LL-ACC-1002') = l_after_to,
                     'Repeated processing changed balances a second time.');
        ROLLBACK TO test10; report_case('Approved held transfers execute once', TRUE, 'Approval executed once; repeat processing was idempotent.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test10; report_case('Approved held transfers execute once', FALSE, SQLERRM);
    END;

    SAVEPOINT test11;
    BEGIN
        UPDATE system_config SET config_value = 'HOLD_FOR_REVIEW' WHERE config_key = 'TRANSFER_MODE';
        l_before_from := balance_for('LL-ACC-1001'); l_before_to := balance_for('LL-ACC-1002');
        create_example(60000, l_from_id, l_to_id);
        pkg_ledgerlens.review_transfer(l_transfer_id, 'REJECTED', 'Test Reviewer', 'Rejected in test.', l_status, l_error);
        require_true(l_status = 'REJECTED', 'Expected rejected transfer.');
        pkg_ledgerlens.process_transfer(l_transfer_id, l_status, l_error);
        require_true(balance_for('LL-ACC-1001') = l_before_from AND balance_for('LL-ACC-1002') = l_before_to,
                     'Rejected transfer changed balances.');
        ROLLBACK TO test11; report_case('Rejected held transfers never execute', TRUE, 'Rejected transfer could not be processed.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test11; report_case('Rejected held transfers never execute', FALSE, SQLERRM);
    END;

    SAVEPOINT test12;
    BEGIN
        create_example(1000, l_from_id, l_to_id);
        SELECT COUNT(*) INTO l_count FROM audit_log
         WHERE transfer_id = l_transfer_id AND action IN ('TRANSFER_CREATED', 'TRANSFER_VALIDATED', 'EXECUTION_COMPLETED', 'STATUS_CHANGED');
        require_true(l_count >= 3, 'Expected lifecycle audit entries were not found.');
        ROLLBACK TO test12; report_case('Lifecycle audit records exist', TRUE, 'Creation, validation and processing/status events were recorded.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test12; report_case('Lifecycle audit records exist', FALSE, SQLERRM);
    END;

    SAVEPOINT test13;
    BEGIN
        UPDATE system_config SET config_value = 'HOLD_FOR_REVIEW' WHERE config_key = 'TRANSFER_MODE';
        create_example(60000, l_from_id, l_to_id);
        pkg_ledgerlens.flag_for_review(l_transfer_id, 'Repeat flag request in test.', 'Y');
        SELECT COUNT(*) INTO l_count FROM review_queue WHERE transfer_id = l_transfer_id AND review_status = 'PENDING';
        require_true(l_count = 1, 'More than one pending review exists for the transfer.');
        ROLLBACK TO test13; report_case('Duplicate pending reviews are prevented', TRUE, 'Repeated flag request kept one pending queue item.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test13; report_case('Duplicate pending reviews are prevented', FALSE, SQLERRM);
    END;

    SAVEPOINT test14;
    BEGIN
        UPDATE system_config SET config_value = 'HOLD_FOR_REVIEW' WHERE config_key = 'TRANSFER_MODE';
        l_before_from := balance_for('LL-ACC-1001'); l_before_to := balance_for('LL-ACC-1002');
        create_example(60000, l_from_id, l_to_id);
        -- Force the destination credit to overflow after the sender debit, exercising the processor savepoint.
        UPDATE accounts SET balance = 9999999999999999.99 WHERE account_id = l_to_id;
        pkg_ledgerlens.review_transfer(l_transfer_id, 'APPROVED', 'Test Reviewer', 'Credit overflow rollback check.', l_status, l_error);
        require_true(l_status = 'FAILED', 'Expected a failed credit against the maximum NUMBER(18,2) balance.');
        require_true(balance_for('LL-ACC-1001') = l_before_from,
                     'Sender debit was not rolled back after the recipient credit failed.');
        require_true(balance_for('LL-ACC-1002') = 9999999999999999.99,
                     'Recipient balance changed after the failed credit.');
        ROLLBACK TO test14;
        require_true(balance_for('LL-ACC-1001') = l_before_from AND balance_for('LL-ACC-1002') = l_before_to,
                     'Rollback did not restore the setup balances.');
        report_case('Rollback restores balances after processing failure', TRUE, 'A simulated credit overflow rolled back the sender debit; outer test rollback restored both seed balances.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test14; report_case('Rollback restores balances after processing failure', FALSE, SQLERRM);
    END;

    SAVEPOINT test15;
    BEGIN
        UPDATE system_config SET config_value = 'HOLD_FOR_REVIEW' WHERE config_key = 'TRANSFER_MODE';
        create_example(60000, l_from_id, l_to_id);
        -- Package processing takes a row lock and is idempotent; two-session race testing is documented separately.
        pkg_ledgerlens.review_transfer(l_transfer_id, 'APPROVED', 'Test Reviewer', NULL, l_status, l_error);
        pkg_ledgerlens.process_transfer(l_transfer_id, l_status, l_error);
        SELECT COUNT(*) INTO l_count FROM audit_log WHERE transfer_id = l_transfer_id AND action = 'EXECUTION_COMPLETED';
        require_true(l_count = 1, 'Transfer executed more than once.');
        ROLLBACK TO test15; report_case('Repeated processing cannot debit twice', TRUE, 'One execution event; concurrent two-session test requires a live Oracle instance.');
    EXCEPTION WHEN OTHERS THEN ROLLBACK TO test15; report_case('Repeated processing cannot debit twice', FALSE, SQLERRM);
    END;

    DBMS_OUTPUT.PUT_LINE('RESULT: ' || l_passes || ' PASS, ' || l_failures || ' FAIL.');
    IF l_failures > 0 THEN RAISE_APPLICATION_ERROR(-20999, 'LedgerLens test suite has failures.'); END IF;
END;
/
