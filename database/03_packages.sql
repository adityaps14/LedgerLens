-- LedgerLens business rules. Package procedures do not COMMIT; the caller owns the transaction.
SET DEFINE OFF

CREATE OR REPLACE PACKAGE pkg_ledgerlens AS
    PROCEDURE validate_transfer(
        p_from_account_id IN NUMBER,
        p_to_account_id   IN NUMBER,
        p_amount          IN NUMBER,
        p_is_valid        OUT CHAR,
        p_error_message   OUT VARCHAR2
    );

    PROCEDURE create_transfer(
        p_from_account_id IN NUMBER,
        p_to_account_id   IN NUMBER,
        p_amount          IN NUMBER,
        p_transfer_id     OUT NUMBER,
        p_reference_number OUT VARCHAR2,
        p_status          OUT VARCHAR2,
        p_risk_flag       OUT CHAR,
        p_error_message   OUT VARCHAR2
    );

    PROCEDURE process_transfer(
        p_transfer_id   IN NUMBER,
        p_status        OUT VARCHAR2,
        p_error_message OUT VARCHAR2
    );

    FUNCTION get_high_value_threshold RETURN NUMBER;

    PROCEDURE set_high_value_threshold(p_threshold IN NUMBER);

    PROCEDURE flag_for_review(
        p_transfer_id IN NUMBER,
        p_reason      IN VARCHAR2,
        p_hold        IN CHAR DEFAULT 'N'
    );

    PROCEDURE review_transfer(
        p_transfer_id   IN NUMBER,
        p_decision      IN VARCHAR2,
        p_reviewer_name IN VARCHAR2,
        p_reviewer_notes IN VARCHAR2,
        p_status        OUT VARCHAR2,
        p_error_message OUT VARCHAR2
    );
END pkg_ledgerlens;
/

CREATE OR REPLACE PACKAGE BODY pkg_ledgerlens AS
    c_money_format CONSTANT VARCHAR2(40) := '999999999999999999D99';
    c_nls_numeric  CONSTANT VARCHAR2(40) := 'NLS_NUMERIC_CHARACTERS=''.,''';

    PROCEDURE add_audit(
        p_transfer_id IN NUMBER,
        p_action      IN VARCHAR2,
        p_details     IN VARCHAR2 DEFAULT NULL,
        p_old_status  IN VARCHAR2 DEFAULT NULL,
        p_new_status  IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        INSERT INTO audit_log (transfer_id, action, old_status, new_status, details)
        VALUES (p_transfer_id, p_action, p_old_status, p_new_status, SUBSTR(p_details, 1, 1000));
    END add_audit;

    FUNCTION get_config_value(p_key IN VARCHAR2) RETURN VARCHAR2 IS
        l_value system_config.config_value%TYPE;
    BEGIN
        SELECT config_value INTO l_value FROM system_config WHERE config_key = p_key;
        RETURN l_value;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20010, 'Missing system configuration: ' || p_key);
    END get_config_value;

    FUNCTION get_high_value_threshold RETURN NUMBER IS
        l_value VARCHAR2(100);
        l_number NUMBER;
    BEGIN
        l_value := get_config_value('HIGH_VALUE_THRESHOLD');
        l_number := TO_NUMBER(TRIM(l_value), c_money_format, c_nls_numeric);
        IF l_number <= 0 THEN
            RAISE_APPLICATION_ERROR(-20011, 'HIGH_VALUE_THRESHOLD must be greater than zero.');
        END IF;
        RETURN l_number;
    EXCEPTION
        WHEN VALUE_ERROR OR INVALID_NUMBER THEN
            RAISE_APPLICATION_ERROR(-20012, 'HIGH_VALUE_THRESHOLD is not a valid monetary amount.');
    END get_high_value_threshold;

    PROCEDURE validate_transfer(
        p_from_account_id IN NUMBER,
        p_to_account_id   IN NUMBER,
        p_amount          IN NUMBER,
        p_is_valid        OUT CHAR,
        p_error_message   OUT VARCHAR2
    ) IS
        l_from_balance accounts.balance%TYPE;
        l_from_status accounts.account_status%TYPE;
        l_to_status accounts.account_status%TYPE;
        l_maximum NUMBER;
        l_mode VARCHAR2(100);
    BEGIN
        p_is_valid := 'N';
        p_error_message := NULL;

        IF p_amount IS NULL OR p_amount <= 0 THEN
            p_error_message := 'Amount must be greater than zero.';
            RETURN;
        END IF;
        IF p_amount <> ROUND(p_amount, 2) THEN
            p_error_message := 'Amount may have no more than two decimal places.';
            RETURN;
        END IF;
        IF p_from_account_id IS NULL OR p_to_account_id IS NULL THEN
            p_error_message := 'Both account IDs are required.';
            RETURN;
        END IF;
        IF p_from_account_id = p_to_account_id THEN
            p_error_message := 'Source and destination accounts must be different.';
            RETURN;
        END IF;

        BEGIN
            SELECT balance, account_status INTO l_from_balance, l_from_status
              FROM accounts WHERE account_id = p_from_account_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            p_error_message := 'Source account does not exist.';
            RETURN;
        END;
        BEGIN
            SELECT account_status INTO l_to_status
              FROM accounts WHERE account_id = p_to_account_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            p_error_message := 'Destination account does not exist.';
            RETURN;
        END;

        IF l_from_status <> 'ACTIVE' OR l_to_status <> 'ACTIVE' THEN
            p_error_message := 'Both accounts must be ACTIVE.';
            RETURN;
        END IF;
        IF l_from_balance < p_amount THEN
            p_error_message := 'Insufficient available balance.';
            RETURN;
        END IF;

        BEGIN
            l_maximum := TO_NUMBER(TRIM(get_config_value('MAX_TRANSFER_AMOUNT')), c_money_format, c_nls_numeric);
            IF l_maximum <= 0 THEN
                p_error_message := 'MAX_TRANSFER_AMOUNT configuration must be greater than zero.';
                RETURN;
            ELSIF p_amount > l_maximum THEN
                p_error_message := 'Amount exceeds the configured maximum transfer amount.';
                RETURN;
            END IF;
            l_mode := UPPER(TRIM(get_config_value('TRANSFER_MODE')));
            IF l_mode IS NULL OR l_mode NOT IN ('FLAG_AND_COMPLETE', 'HOLD_FOR_REVIEW') THEN
                p_error_message := 'TRANSFER_MODE must be FLAG_AND_COMPLETE or HOLD_FOR_REVIEW.';
                RETURN;
            END IF;
            -- A valid threshold is required for every transfer, even a low-value transfer.
            IF get_high_value_threshold() <= 0 THEN
                p_error_message := 'HIGH_VALUE_THRESHOLD must be greater than zero.';
                RETURN;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                p_error_message := 'Transfer configuration error: ' || SQLERRM;
                RETURN;
        END;

        p_is_valid := 'Y';
    END validate_transfer;

    PROCEDURE flag_for_review(
        p_transfer_id IN NUMBER,
        p_reason      IN VARCHAR2,
        p_hold        IN CHAR DEFAULT 'N'
    ) IS
        l_status transfers.status%TYPE;
        l_reason VARCHAR2(500);
        l_count PLS_INTEGER;
    BEGIN
        SAVEPOINT ll_flag_sp;
        IF p_reason IS NULL OR TRIM(p_reason) IS NULL THEN
            RAISE_APPLICATION_ERROR(-20020, 'A review reason is required.');
        END IF;
        IF NVL(UPPER(p_hold), 'N') NOT IN ('Y', 'N') THEN
            RAISE_APPLICATION_ERROR(-20021, 'p_hold must be Y or N.');
        END IF;
        SELECT status INTO l_status FROM transfers WHERE transfer_id = p_transfer_id FOR UPDATE;
        IF UPPER(NVL(p_hold, 'N')) = 'Y' AND l_status NOT IN ('PENDING', 'HELD_FOR_REVIEW') THEN
            RAISE_APPLICATION_ERROR(-20023, 'Only a pending transfer can be placed on hold.');
        ELSIF UPPER(NVL(p_hold, 'N')) = 'N' AND l_status <> 'COMPLETED' THEN
            RAISE_APPLICATION_ERROR(-20024, 'Only a completed transfer can be flagged without a hold.');
        END IF;
        l_reason := SUBSTR(TRIM(p_reason), 1, 500);

        UPDATE transfers
           SET risk_flag = 'Y', risk_reason = l_reason,
               status = CASE WHEN UPPER(NVL(p_hold, 'N')) = 'Y' THEN 'HELD_FOR_REVIEW' ELSE status END
         WHERE transfer_id = p_transfer_id;

        SELECT COUNT(*) INTO l_count FROM review_queue
         WHERE transfer_id = p_transfer_id AND review_status = 'PENDING';
        IF l_count = 0 THEN
            INSERT INTO review_queue (transfer_id, reason, review_status)
            VALUES (p_transfer_id, l_reason, 'PENDING');
        END IF;
        add_audit(p_transfer_id, 'FLAGGED_FOR_REVIEW', l_reason, l_status,
                  CASE WHEN UPPER(NVL(p_hold, 'N')) = 'Y' THEN 'HELD_FOR_REVIEW' ELSE l_status END);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK TO ll_flag_sp;
            RAISE_APPLICATION_ERROR(-20022, 'Transfer not found for review.');
        WHEN OTHERS THEN
            ROLLBACK TO ll_flag_sp;
            RAISE;
    END flag_for_review;

    PROCEDURE process_transfer(
        p_transfer_id   IN NUMBER,
        p_status        OUT VARCHAR2,
        p_error_message OUT VARCHAR2
    ) IS
        l_status transfers.status%TYPE;
        l_from_id transfers.from_account_id%TYPE;
        l_to_id transfers.to_account_id%TYPE;
        l_amount transfers.amount%TYPE;
        l_balance accounts.balance%TYPE;
        l_account_status accounts.account_status%TYPE;
        l_from_balance accounts.balance%TYPE;
        l_from_status accounts.account_status%TYPE;
        l_to_status accounts.account_status%TYPE;
        l_count PLS_INTEGER := 0;
        l_review_status review_queue.review_status%TYPE;
        l_is_valid CHAR(1);
        l_validation_message VARCHAR2(1000);
        l_failure VARCHAR2(1000);
        CURSOR c_account_ids IS
            SELECT account_id FROM accounts
             WHERE account_id IN (l_from_id, l_to_id)
             ORDER BY account_id;
    BEGIN
        p_status := NULL;
        p_error_message := NULL;
        BEGIN
            SELECT status, from_account_id, to_account_id, amount
              INTO l_status, l_from_id, l_to_id, l_amount
              FROM transfers WHERE transfer_id = p_transfer_id FOR UPDATE;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            p_status := 'FAILED';
            p_error_message := 'Transfer does not exist.';
            RETURN;
        END;

        IF l_status = 'COMPLETED' THEN
            p_status := l_status;
            p_error_message := 'Transfer has already completed; no balances were changed.';
            RETURN;
        ELSIF l_status = 'FAILED' OR l_status = 'REJECTED' THEN
            p_status := l_status;
            p_error_message := 'A failed or rejected transfer cannot be executed.';
            RETURN;
        ELSIF l_status = 'HELD_FOR_REVIEW' THEN
            BEGIN
                SELECT review_status INTO l_review_status FROM review_queue
                 WHERE transfer_id = p_transfer_id AND review_status IN ('PENDING', 'APPROVED')
                 ORDER BY created_at DESC FETCH FIRST 1 ROW ONLY;
            EXCEPTION WHEN NO_DATA_FOUND THEN
                p_status := l_status;
                p_error_message := 'Held transfer has no review record.';
                RETURN;
            END;
            IF l_review_status <> 'APPROVED' THEN
                p_status := l_status;
                p_error_message := 'Held transfer must be approved before processing.';
                RETURN;
            END IF;
        ELSIF l_status <> 'PENDING' THEN
            p_status := l_status;
            p_error_message := 'Transfer is not in a processable state.';
            RETURN;
        END IF;

        SAVEPOINT ll_process_sp;
        BEGIN
            -- Lock one row at a time in ascending ID order, independent of transfer direction.
            FOR r_account IN c_account_ids LOOP
                SELECT balance, account_status INTO l_balance, l_account_status
                  FROM accounts WHERE account_id = r_account.account_id FOR UPDATE;
                IF r_account.account_id = l_from_id THEN
                    l_from_balance := l_balance;
                    l_from_status := l_account_status;
                ELSIF r_account.account_id = l_to_id THEN
                    l_to_status := l_account_status;
                END IF;
                l_count := l_count + 1;
            END LOOP;

            IF l_count <> 2 THEN
                RAISE_APPLICATION_ERROR(-20030, 'One or both accounts no longer exist.');
            END IF;
            IF l_from_status <> 'ACTIVE' OR l_to_status <> 'ACTIVE' THEN
                RAISE_APPLICATION_ERROR(-20031, 'Both accounts must still be ACTIVE.');
            END IF;
            IF l_from_balance < l_amount THEN
                RAISE_APPLICATION_ERROR(-20032, 'Insufficient available balance at execution time.');
            END IF;

            validate_transfer(l_from_id, l_to_id, l_amount, l_is_valid, l_validation_message);
            IF l_is_valid <> 'Y' THEN
                RAISE_APPLICATION_ERROR(-20033, l_validation_message);
            END IF;

            UPDATE accounts SET balance = balance - l_amount WHERE account_id = l_from_id;
            UPDATE accounts SET balance = balance + l_amount WHERE account_id = l_to_id;
            UPDATE transfers SET status = 'COMPLETED', completed_at = SYSTIMESTAMP
             WHERE transfer_id = p_transfer_id;
            add_audit(p_transfer_id, 'EXECUTION_COMPLETED', 'Source debited and destination credited atomically.', l_status, 'COMPLETED');
            p_status := 'COMPLETED';
        EXCEPTION
            WHEN OTHERS THEN
                l_failure := SQLERRM;
                ROLLBACK TO ll_process_sp;
                UPDATE transfers SET status = 'FAILED', completed_at = NULL
                 WHERE transfer_id = p_transfer_id;
                add_audit(p_transfer_id, 'PROCESSING_FAILED', l_failure, l_status, 'FAILED');
                p_status := 'FAILED';
                p_error_message := l_failure;
        END;
    END process_transfer;

    PROCEDURE create_transfer(
        p_from_account_id IN NUMBER,
        p_to_account_id   IN NUMBER,
        p_amount          IN NUMBER,
        p_transfer_id     OUT NUMBER,
        p_reference_number OUT VARCHAR2,
        p_status          OUT VARCHAR2,
        p_risk_flag       OUT CHAR,
        p_error_message   OUT VARCHAR2
    ) IS
        l_valid CHAR(1);
        l_validation_message VARCHAR2(1000);
        l_threshold NUMBER;
        l_mode VARCHAR2(100);
        l_process_message VARCHAR2(1000);
        l_process_status VARCHAR2(24);
    BEGIN
        p_transfer_id := NULL;
        p_reference_number := NULL;
        p_status := 'FAILED';
        p_risk_flag := 'N';
        p_error_message := NULL;
        SAVEPOINT ll_create_sp;

        -- Invalid amounts and unknown account IDs cannot satisfy the table constraints;
        -- return a clear failure without inserting a transfer row.
        IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> ROUND(p_amount, 2) THEN
            p_error_message := CASE WHEN p_amount IS NULL OR p_amount <= 0
                                    THEN 'Amount must be greater than zero.'
                                    ELSE 'Amount may have no more than two decimal places.' END;
            RETURN;
        END IF;
        IF p_from_account_id = p_to_account_id THEN
            p_error_message := 'Source and destination accounts must be different.';
            RETURN;
        END IF;
        DECLARE
            l_dummy NUMBER;
        BEGIN
            SELECT account_id INTO l_dummy FROM accounts WHERE account_id = p_from_account_id;
            SELECT account_id INTO l_dummy FROM accounts WHERE account_id = p_to_account_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            p_error_message := 'Source or destination account does not exist.';
            RETURN;
        END;

        INSERT INTO transfers (reference_number, from_account_id, to_account_id, amount, status)
        VALUES ('PENDING-' || RAWTOHEX(SYS_GUID()),
                p_from_account_id, p_to_account_id, p_amount, 'PENDING')
        RETURNING transfer_id INTO p_transfer_id;

        p_reference_number := 'LL-' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3') || '-' || LPAD(p_transfer_id, 8, '0');
        UPDATE transfers SET reference_number = p_reference_number WHERE transfer_id = p_transfer_id;
        add_audit(p_transfer_id, 'TRANSFER_CREATED', 'Transfer request recorded.', NULL, 'PENDING');

        validate_transfer(p_from_account_id, p_to_account_id, p_amount, l_valid, l_validation_message);
        IF l_valid <> 'Y' THEN
            UPDATE transfers SET status = 'FAILED' WHERE transfer_id = p_transfer_id;
            add_audit(p_transfer_id, 'VALIDATION_FAILED', l_validation_message, 'PENDING', 'FAILED');
            p_status := 'FAILED';
            p_error_message := l_validation_message;
            RETURN;
        END IF;
        add_audit(p_transfer_id, 'TRANSFER_VALIDATED', 'Accounts, amount, balance and configured limits passed validation.');

        l_threshold := get_high_value_threshold();
        l_mode := UPPER(TRIM(get_config_value('TRANSFER_MODE')));
        IF p_amount >= l_threshold THEN
            p_risk_flag := 'Y';
            IF l_mode = 'HOLD_FOR_REVIEW' THEN
                flag_for_review(p_transfer_id,
                    'Amount ' || TO_CHAR(p_amount, 'FM9999999999999990D00', c_nls_numeric) ||
                    ' is at or above the configured high-value threshold of ' ||
                    TO_CHAR(l_threshold, 'FM9999999999999990D00', c_nls_numeric) || '.', 'Y');
                p_status := 'HELD_FOR_REVIEW';
                RETURN;
            END IF;
        END IF;

        process_transfer(p_transfer_id, l_process_status, l_process_message);
        p_status := l_process_status;
        p_error_message := l_process_message;
        IF p_risk_flag = 'Y' AND l_process_status = 'COMPLETED' THEN
            flag_for_review(p_transfer_id,
                'Amount ' || TO_CHAR(p_amount, 'FM9999999999999990D00', c_nls_numeric) ||
                ' is at or above the configured high-value threshold of ' ||
                TO_CHAR(l_threshold, 'FM9999999999999990D00', c_nls_numeric) || '.', 'N');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO ll_create_sp;
            p_transfer_id := NULL;
            p_reference_number := NULL;
            p_status := 'FAILED';
            p_risk_flag := 'N';
            p_error_message := SQLERRM;
    END create_transfer;

    PROCEDURE set_high_value_threshold(p_threshold IN NUMBER) IS
        l_old_value system_config.config_value%TYPE;
        l_new_value VARCHAR2(100);
        l_operator_count PLS_INTEGER;
    BEGIN
        SAVEPOINT ll_threshold_sp;
        IF p_threshold IS NULL OR p_threshold <= 0 OR p_threshold > 9999999999999999.99
           OR p_threshold <> ROUND(p_threshold, 2) THEN
            RAISE_APPLICATION_ERROR(-20040, 'Threshold must be positive and have no more than two decimal places.');
        END IF;
        SELECT COUNT(*) INTO l_operator_count FROM system_operators
         WHERE username = UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'));
        IF l_operator_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20041, 'Current database user is not an authorized LedgerLens operator.');
        END IF;

        l_new_value := TO_CHAR(p_threshold, 'FM9999999999999990D00', c_nls_numeric);
        BEGIN
            SELECT config_value INTO l_old_value FROM system_config WHERE config_key = 'HIGH_VALUE_THRESHOLD' FOR UPDATE;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20042, 'HIGH_VALUE_THRESHOLD configuration is missing.');
        END;
        UPDATE system_config SET config_value = l_new_value, updated_at = SYSTIMESTAMP
         WHERE config_key = 'HIGH_VALUE_THRESHOLD';
        INSERT INTO config_audit (config_key, old_value, new_value, changed_by)
        VALUES ('HIGH_VALUE_THRESHOLD', l_old_value, l_new_value, UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER')));
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO ll_threshold_sp;
            RAISE;
    END set_high_value_threshold;

    PROCEDURE review_transfer(
        p_transfer_id    IN NUMBER,
        p_decision       IN VARCHAR2,
        p_reviewer_name  IN VARCHAR2,
        p_reviewer_notes IN VARCHAR2,
        p_status         OUT VARCHAR2,
        p_error_message  OUT VARCHAR2
    ) IS
        l_transfer_status transfers.status%TYPE;
        l_risk_flag transfers.risk_flag%TYPE;
        l_review_id review_queue.review_id%TYPE;
        l_review_status review_queue.review_status%TYPE;
        l_decision VARCHAR2(12) := UPPER(TRIM(p_decision));
        l_process_status VARCHAR2(24);
        l_process_error VARCHAR2(1000);
        l_reviewer_count PLS_INTEGER;
    BEGIN
        p_error_message := NULL;
        p_status := 'FAILED';
        SAVEPOINT ll_review_sp;
        IF l_decision IS NULL OR l_decision NOT IN ('APPROVED', 'REJECTED') THEN
            p_status := 'FAILED';
            p_error_message := 'Decision must be APPROVED or REJECTED.';
            RETURN;
        END IF;
        IF p_reviewer_name IS NULL OR TRIM(p_reviewer_name) IS NULL THEN
            p_status := 'FAILED';
            p_error_message := 'Reviewer name is required.';
            RETURN;
        END IF;
        SELECT COUNT(*) INTO l_reviewer_count FROM system_reviewers
         WHERE username = UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'));
        IF l_reviewer_count = 0 THEN
            p_error_message := 'Current database user is not an authorized LedgerLens reviewer.';
            RETURN;
        END IF;

        SELECT status, risk_flag INTO l_transfer_status, l_risk_flag
          FROM transfers WHERE transfer_id = p_transfer_id FOR UPDATE;
        IF l_transfer_status <> 'HELD_FOR_REVIEW'
           AND NOT (l_transfer_status = 'COMPLETED' AND l_risk_flag = 'Y') THEN
            p_status := l_transfer_status;
            p_error_message := 'Only a held transfer or completed flagged transfer can be reviewed.';
            RETURN;
        END IF;
        BEGIN
            SELECT review_id, review_status INTO l_review_id, l_review_status
              FROM review_queue WHERE transfer_id = p_transfer_id AND review_status = 'PENDING'
              FOR UPDATE;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            p_status := l_transfer_status;
            p_error_message := 'No pending review exists for this transfer.';
            RETURN;
        END;

        UPDATE review_queue
           SET review_status = l_decision,
               reviewer_notes = SUBSTR(p_reviewer_notes, 1, 1000),
               reviewed_at = SYSTIMESTAMP
         WHERE review_id = l_review_id;
        add_audit(p_transfer_id, CASE WHEN l_decision = 'APPROVED' THEN 'REVIEW_APPROVED' ELSE 'REVIEW_REJECTED' END,
                  'Database user: ' || UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER')) ||
                  '; Reviewer label: ' || TRIM(p_reviewer_name) ||
                  CASE WHEN p_reviewer_notes IS NOT NULL THEN '; Notes: ' || p_reviewer_notes END);

        IF l_decision = 'REJECTED' THEN
            IF l_transfer_status = 'HELD_FOR_REVIEW' THEN
                UPDATE transfers SET status = 'REJECTED' WHERE transfer_id = p_transfer_id;
                p_status := 'REJECTED';
            ELSE
                -- Completed transactions are dispositioned in the queue; rejection does not reverse funds.
                p_status := 'COMPLETED';
            END IF;
            RETURN;
        END IF;

        IF l_transfer_status = 'COMPLETED' THEN
            -- In FLAG_AND_COMPLETE mode approval records a review decision without re-execution.
            p_status := 'COMPLETED';
            RETURN;
        END IF;

        process_transfer(p_transfer_id, l_process_status, l_process_error);
        p_status := l_process_status;
        p_error_message := l_process_error;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_status := 'FAILED';
            p_error_message := 'Transfer does not exist.';
        WHEN OTHERS THEN
            ROLLBACK TO ll_review_sp;
            p_status := 'FAILED';
            p_error_message := SQLERRM;
    END review_transfer;
END pkg_ledgerlens;
/

SHOW ERRORS PACKAGE pkg_ledgerlens
SHOW ERRORS PACKAGE BODY pkg_ledgerlens
PROMPT Package compiled if SHOW ERRORS reports no errors.
