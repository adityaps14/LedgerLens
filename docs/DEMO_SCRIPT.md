# Five-Minute Demonstration Script

## Before presenting

Install the scripts in order and run `database/08_reset.sql` only if you want a clean demo state. Verify the account balances, choose either the dashboard or SQL Developer, and have the report queries ready. Do not claim that tests passed unless `07_tests.sql` has actually run and produced the output you show.

## 0:00–0:40 — Introduce the project

“LedgerLens is an educational Oracle PL/SQL transaction-monitoring system. The data is fictional. Oracle owns the transfer rules, and the optional Flask page is just a user interface. A high-value alert requests review; it does not prove fraud.”

Show the project diagram or dashboard. Identify customers, accounts, transfers, review queue and audit log.

## 0:40–1:30 — Show schema and package

Open `database/01_schema.sql` and point to foreign keys, balance and status checks, and `NUMBER(18,2)`. Open `03_packages.sql` and explain that the public package specification separates the interface from the implementation. Mention that package calls do not commit: the caller decides when to commit.

## 1:30–2:20 — Normal transfer

Submit a `1000.00` transfer from `LL-ACC-1001` to `LL-ACC-1002` using the dashboard or `06_demo.sql`. Show the `COMPLETED` status and the two balance changes. Explain that the processor locks both account rows in ascending account ID order and updates them in one transaction.

## 2:20–3:10 — High-value and hold modes

Submit `60000.00` with the default `50000.00` threshold. In `FLAG_AND_COMPLETE`, show the completed state, `risk_flag = Y`, review queue item and reason. Then point out `HOLD_FOR_REVIEW`: held transfers remain unexecuted until approval. If time allows, update `TRANSFER_MODE`, create a second high-value transfer, and show the unchanged balances.

## 3:10–4:00 — Review and audit

Approve or reject the held request. Explain that approval rechecks status and available balance, while rejection cannot execute. Open transfer detail or the audit report and point to creation, validation, status and review events. Mention the account timestamp and status audit triggers.

## 4:00–4:40 — Reports and tests

Run `05_reports.sql` to show balances, transfers, high-value flags and daily/status counts. Run `07_tests.sql` only when Oracle is installed, and show the output as observed. Explain that its sequential repeat test is not a multi-session concurrency stress test.

## 4:40–5:00 — Close

“The project demonstrates relational constraints, packages, procedures, a function, triggers, a cursor, row locking, exception handling, review workflow and SQL reporting. It is a learning prototype and would need much stronger identity, authorization and operational controls before any real financial use.”
