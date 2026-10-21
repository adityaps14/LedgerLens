# Test Plan and Validation Record

## Scope

`database/07_tests.sql` is an Oracle SQL/PLSQL suite with isolated savepoints. Each case prints `PASS` or `FAIL`, then rolls back its test data. It covers normal execution, inclusive threshold classification, threshold changes, insufficient funds, invalid amounts, same-account and unknown-account rejection, inactive accounts, hold mode, approval, rejection, audit events, duplicate pending reviews, failure revalidation/rollback, and sequential repeated processing.

Each case is independently reported. The script ends with an Oracle application error if any case failed. The test data is found by synthetic account numbers rather than assuming generated identity values.

## Running the suite

1. Install `01_schema.sql`, `02_seed_data.sql`, `03_packages.sql`, and `04_triggers.sql` in order.
2. Connect as the seeded schema owner (needed for threshold-change tests).
3. Run `@database/07_tests.sql` in SQLcl or SQL Developer's Run Script mode.
4. Save the actual output for the project report; do not copy expected results as if they were observed.

## Cases in the suite

| # | Check | Expected behavior |
|---:|---|---|
| 1 | Normal transfer 1000 | Completed; source debit and recipient credit |
| 2 | High-value transfer 60000 | Completed, flagged, one pending review in default mode |
| 3 | Amount equals the configured threshold | Equality is flagged |
| 4 | Completed transfer review disposition | Rejection updates queue only and never reverses funds |
| 5 | Threshold temporarily raised to 70000 | 60000 is no longer flagged; configuration rolls back |
| 6 | Amount exceeds available balance | Failed and no account balance changes |
| 7 | Zero and negative amount | Failed with amount validation message |
| 8 | Same account | Failed before a transfer row is created |
| 9 | Unknown account ID | Failed with a clear missing-account message |
| 10 | Inactive source | Failed with active-account message |
| 11 | Hold mode | Held and no balance changes before review |
| 12 | Approve held transfer; process again | Executes once and no second balance movement |
| 13 | Reject held transfer | Rejected and cannot execute |
| 14 | Lifecycle audit | Creation, validation, execution/status entries exist |
| 15 | Repeated flag request | Exactly one pending review remains |
| 16 | Recipient credit overflows `NUMBER(18,2)` after sender debit | Package savepoint rolls back debit; outer test rollback restores setup |
| 17 | Repeated sequential processing | Exactly one execution event; same transfer cannot debit twice |

## Concurrency follow-up

The suite's final case is repeated processing in one session, not a concurrent stress test. To exercise two-session serialization on Oracle, create a held transfer, approve it from two SQLcl sessions at nearly the same time, commit one, then confirm the other observes a completed state and account balances moved once. Capture both sessions' outputs. This concurrency scenario was not run unless separately recorded by the student.

## Local authoring-environment checks

The authoring environment had Python 3.13.14 and Flask installed, but did not have `oracledb`, `python-dotenv`, SQL*Plus, SQLcl, or configured Oracle connection settings. Results: `compileall` passed; a Flask smoke check rendered five GET pages and exercised three POST handlers using stubbed database calls; required project files and local Markdown links resolved. These checks do not verify database integration. Oracle compilation, schema installation, a live dashboard connection, and `07_tests.sql` were not run and must not be reported as passed.
