# Security and Limitations

LedgerLens is an educational demonstration using fictional records. It is not intended for real banking, payment processing, fraud decisions or regulated data.

## Included safeguards

- No credentials or real customer data are included.
- `.env` is ignored by Git; `.env.example` contains placeholders only.
- Python SQL statements use bind variables for values.
- Form POSTs require a session CSRF token.
- The Flask development server binds to `127.0.0.1` by default.
- The package restricts threshold updates to database usernames present in `SYSTEM_OPERATORS` and audits the change.
- The package restricts review decisions to database usernames present in `SYSTEM_REVIEWERS` and records the session user; the displayed reviewer label is not authentication.
- Transfer updates use Oracle row locks, state checks and savepoints.

## Important limitations

- The dashboard has no login, user account system or independent reviewer identity. The reviewer name is a submitted label/environment setting, not proof of identity. Anyone able to use the local dashboard while it is connected as a reviewer can make decisions. Do not expose this app to a network or internet.
- The dashboard's Oracle connection account should be a restricted application account with only required access. For a fuller deployment, move tables into an owner schema and grant only package execute and required read privileges; do not use a privileged administrator account.
- The package and schema have not been compiled or run in an Oracle environment in the authoring session. Verify against Oracle 19c+ before relying on the code for a presentation.
- The test suite performs sequential repeated-call checks, not a multi-session concurrency load test.
- Audit tables are ordinary application tables. A user with sufficient privileges can alter them; no cryptographic tamper-evidence or immutable audit archive is implemented.
- No encryption at rest, secret vault, production session management, rate limiting, monitoring, backup/restore process or disaster recovery procedures are provided.
- The high-value rule is a threshold demonstration, not statistical fraud detection. A flagged amount is not proof of wrongdoing.

Use a disposable Oracle schema, keep it local, and use only the supplied synthetic records during the lab.
