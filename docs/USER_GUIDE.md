# User Guide

## 1. Prepare Oracle

Install Oracle Database 19c+ or Oracle Database Free and SQL Developer or SQLcl. Create or choose a disposable schema for the exercise and connect as its owner. Oracle Free installations commonly expose a PDB service such as `FREEPDB1`; use the service name configured on your installation.

Open a PowerShell terminal in the repository:

```powershell
Set-Location C:\path\to\LedgerLens
sql YOUR_SCHEMA@//localhost:1521/FREEPDB1
```

Enter the password at the SQLcl prompt, then execute:

```sql
@database/01_schema.sql
@database/02_seed_data.sql
@database/03_packages.sql
@database/04_triggers.sql
```

For SQL Developer, create a connection to the same PDB/schema. Open each file in order and use **Run Script (F5)**. Check the Script Output for compilation errors. `01_schema.sql` is a one-time create script and is not a migration or reset script.

## 2. Check the seeded setup

```sql
SELECT account_number, balance, account_status FROM accounts ORDER BY account_number;
SELECT config_key, config_value FROM system_config ORDER BY config_key;
```

The seed balances are 250000, 40000, 125000, 5000, and 75000. Account `LL-ACC-1005` is inactive. All data is fictional.

The schema owner is seeded as both the initial threshold operator and reviewer. To authorize another database username, connect as the schema owner and add the uppercase Oracle username to the appropriate list:

```sql
INSERT INTO system_operators (username) VALUES ('APP_OPERATOR');
INSERT INTO system_reviewers (username) VALUES ('APP_REVIEWER');
COMMIT;
```

## 3. Create transfers with SQL

Use `database/06_demo.sql` for a complete, committed demonstration. To make a single request manually, resolve account IDs and call the package:

```sql
DECLARE
  l_from NUMBER;
  l_to NUMBER;
  l_id NUMBER;
  l_reference VARCHAR2(40);
  l_status VARCHAR2(24);
  l_risk CHAR(1);
  l_error VARCHAR2(1000);
BEGIN
  SELECT account_id INTO l_from FROM accounts WHERE account_number = 'LL-ACC-1001';
  SELECT account_id INTO l_to FROM accounts WHERE account_number = 'LL-ACC-1002';
  pkg_ledgerlens.create_transfer(l_from, l_to, 1000,
    l_id, l_reference, l_status, l_risk, l_error);
  DBMS_OUTPUT.PUT_LINE('ID=' || l_id || ' REF=' || l_reference ||
    ' STATUS=' || l_status || ' FLAG=' || l_risk || ' ERROR=' || l_error);
  COMMIT; -- Package routines deliberately do not commit.
END;
/
```

SQL Developer: enable the DBMS Output panel for the connection before running the block. To discard the operation instead, issue `ROLLBACK` instead of `COMMIT`.

## 4. Try hold-for-review mode

```sql
UPDATE system_config SET config_value = 'HOLD_FOR_REVIEW' WHERE config_key = 'TRANSFER_MODE';
COMMIT;
```

Create a `60000` transfer. It should return `HELD_FOR_REVIEW`; balances remain unchanged. Review it using the dashboard or a PL/SQL call:

```sql
DECLARE
  l_status VARCHAR2(24);
  l_error VARCHAR2(1000);
BEGIN
  pkg_ledgerlens.review_transfer(TRANSFER_ID, 'APPROVED', 'Classroom Reviewer',
    'Verified for demonstration.', l_status, l_error);
  DBMS_OUTPUT.PUT_LINE(l_status || ' ' || l_error);
  COMMIT;
END;
/
```

Replace `TRANSFER_ID` with the numeric ID returned by creation. To reject instead, pass `REJECTED`; a rejected request cannot be processed.

In the default `FLAG_AND_COMPLETE` mode, high-value transfers are already completed before they enter the queue. Approving or rejecting those queue entries records a review disposition only; rejection does not reverse a completed transfer or its balance movements.

Restore the default mode after the exercise:

```sql
UPDATE system_config SET config_value = 'FLAG_AND_COMPLETE' WHERE config_key = 'TRANSFER_MODE';
COMMIT;
```

## 5. Reports and tests

Run `@database/05_reports.sql` for account, transfer, review, status, daily aggregate and audit reports. Change the example transfer ID in its audit query as needed. Run `@database/07_tests.sql` for the Oracle PL/SQL suite; read every printed outcome and resolve any failure before presenting results.

## 6. Run the Flask dashboard

In PowerShell:

```powershell
Set-Location C:\path\to\LedgerLens
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
Copy-Item .env.example .env
notepad .env
python .\app\app.py
```

Set Oracle service settings, reviewer display name and a random secret key in `.env`. Open `http://127.0.0.1:5000`. If Oracle Python Thick mode is required by your client setup, install/configure the Oracle Client libraries before starting the app; Thin mode is the default and works for many Oracle Database connections.

## 7. Reset classroom data

`database/08_reset.sql` deletes demo transfer, audit and review history, resets the five seeded balances, and restores default configuration. It prompts for the exact response `YES` and commits the reset. Run only in the dedicated classroom schema. It does not drop database objects or reset identity sequences.
