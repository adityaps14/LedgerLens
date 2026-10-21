# Viva Questions and Beginner-Friendly Answers

1. **What is LedgerLens?**  It is a classroom project showing how an Oracle database can validate, process, flag and audit fictional account transfers.
2. **Why use Oracle PL/SQL?**  PL/SQL lets us keep database rules and multi-step operations close to the data and execute them as a stored program.
3. **What is a primary key?**  It uniquely identifies a row, such as `account_id` for an account.
4. **What is a foreign key?**  It ensures a referenced row exists. A transfer's source and destination IDs must refer to accounts.
5. **Why is money stored as NUMBER?**  Decimal `NUMBER(18,2)` avoids binary floating-point rounding behavior for currency-like values.
6. **What does a CHECK constraint do?**  It rejects rows that violate a rule, such as a negative balance or an unknown status.
7. **What is a PL/SQL package?**  It groups related public routine declarations and their implementation under one database object.
8. **What is the package specification?**  It is the public interface that callers use; the package body contains routine implementations.
9. **What is a procedure?**  A named PL/SQL routine that performs work and may return values through OUT parameters.
10. **What is a function?**  A routine that returns one value. `GET_HIGH_VALUE_THRESHOLD` returns the configured threshold.
11. **What is a trigger?**  Database code that runs automatically when a defined table event happens. LedgerLens uses triggers sparingly for timestamps and status audit.
12. **What is a cursor?**  A PL/SQL mechanism for handling rows from a query. The processor uses a cursor to lock the two accounts in a consistent order.
13. **Why lock account rows?**  To prevent two concurrent transactions from spending the same available balance at the same time.
14. **Why lock rows in ascending account ID order?**  Opposite-direction transfers then try to acquire their shared account locks in the same order, reducing deadlock risk.
15. **What does atomic transfer mean here?**  Debit and credit belong to the same database transaction. If processing fails, neither balance movement remains.
16. **Why does the package avoid COMMIT?**  The caller may have other related work. Leaving the transaction to the caller avoids committing unrelated changes unexpectedly.
17. **What is a savepoint?**  A marker inside a transaction. The package can roll back its processing work to that point while leaving earlier caller work intact.
18. **What is an audit log?**  A history of meaningful lifecycle and status events, including validation, execution, review and failures.
19. **When is a transfer high-value?**  When its amount is greater than or equal to `HIGH_VALUE_THRESHOLD`; equality counts.
20. **What are the two operating modes?**  `FLAG_AND_COMPLETE` executes then flags a valid high-value transfer; `HOLD_FOR_REVIEW` queues it and waits before moving balances.
21. **Does a high-value flag mean fraud?**  No. It is only a configurable review signal in this educational project.
22. **What happens if a held transfer is rejected?**  Its transfer state becomes `REJECTED`; processing refuses it, and balances remain unchanged.
23. **Why check balance again during approval?**  Other transfers may have changed balances after the request was held, so the approval path checks the current state.
24. **How is duplicate pending review prevented?**  Package logic checks for an existing pending item, and a unique function-based index enforces at most one pending row per transfer.
25. **What does the status trigger record?**  It adds a generic audit entry whenever `transfers.status` changes. Package events add context such as a review reason.
26. **How does threshold update authorization work?**  The package checks that the database session user is listed in `SYSTEM_OPERATORS`, then writes a config audit row.
27. **Why are SQL binds used in the Flask app?**  Bind variables separate data from SQL syntax and help prevent input from changing the query structure.
28. **Does the Flask app simulate Oracle data?**  No. It requires a real Oracle connection and displays a connection error if configuration or Oracle access is missing.
29. **What is the role of the test suite?**  It checks expected database behavior with isolated savepoints and prints `PASS` or `FAIL` for each case.
30. **Which tests need two sessions?**  A real race/concurrency check needs two Oracle sessions; the included suite only tests sequential repeat processing.
31. **What is an identity column?**  An Oracle column whose value is generated automatically for inserted rows.
32. **What is one limitation of this project?**  It lacks production authentication, external payment integration, operational controls and a real fraud-detection model.
