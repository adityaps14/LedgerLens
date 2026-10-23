# LedgerLens

LedgerLens is an educational Oracle SQL/PLSQL transaction-monitoring and audit project. It demonstrates this workflow:

**Create transfer → validate → execute or hold → audit → flag → report**

It is designed for a database/PLSQL lab, a student project report, and a portfolio demonstration. It is not a production banking system or certified fraud-detection product. All seeded people and account numbers are fictional. A high-value flag is a review signal, not proof of fraud.

## Features

- Oracle relational schema with constraints, foreign keys, indexes, timestamps and identity columns.
- `PKG_LEDGERLENS` package for validation, transfer processing, threshold configuration, risk flags and review decisions.
- Account row locking in ascending account ID order, execution-time revalidation, atomic balance changes, and caller-owned transactions.
- Two high-value modes: `FLAG_AND_COMPLETE` (seeded default) and `HOLD_FOR_REVIEW`.
- Lifecycle audit log, configuration audit history, pending review queue, SQL reports and a rollback-based PL/SQL suite.
- Optional Flask dashboard using `python-oracledb`; the application calls the PL/SQL package for business operations.

## Requirements

- Oracle Database 19c or later (Oracle Database Free is suitable), with a dedicated schema and access through SQL Developer or SQLcl.
- Python 3.11+ for the optional dashboard (the source also works with supported newer Python releases).
- Git for version control. GitHub hosting is optional.

No Oracle client, SQLcl, or Oracle Python driver was available in the authoring environment. The Oracle scripts and Flask integration are included, but database compilation, execution, and live connection remain to be verified on an Oracle instance. See [the test plan](docs/TEST_PLAN.md) and [the project report](docs/PROJECT_REPORT.md) for the recorded validation scope.

## Project layout

```text
LedgerLens/
├── app/                  # Flask dashboard and templates
├── database/             # Ordered Oracle setup, demo, reports, tests, reset
├── docs/                 # Report, design, guide, test plan, viva materials
├── scripts/              # Local environment check
├── .env.example          # Placeholder configuration only
├── .gitignore
├── LICENSE
├── README.md
└── requirements.txt
```

## Install the Oracle schema

Use a fresh, dedicated schema. `01_schema.sql` creates objects and intentionally does not drop anything; do not rerun it in a schema where these objects already exist. Connect SQL Developer or SQLcl as the schema owner. The seed script registers that session user as the initial threshold operator.

From PowerShell, after installing SQLcl and connecting to Oracle Free (replace the schema and service as needed):

```powershell
Set-Location .\LedgerLens
sql LEDGERLENS@//localhost:1521/FREEPDB1
```

At the SQLcl prompt, run the scripts in this order:

```sql
@database/01_schema.sql
@database/02_seed_data.sql
@database/03_packages.sql
@database/04_triggers.sql
```

In SQL Developer, open each script in order and choose **Run Script (F5)** while connected to the new schema. Verify that `SHOW ERRORS` reports no package or trigger errors. For Windows path examples and Oracle connection notes, see the [user guide](docs/USER_GUIDE.md).

## Run database tests and reports

With the schema installed, run the repeatable PL/SQL test suite:

```sql
@database/07_tests.sql
```

Every case prints `PASS` or `FAIL` and rolls back its changes. A live two-session concurrency test is described separately because one session cannot model an actual race. Do not report the suite as passing until it has run against Oracle.

Run reports with:

```sql
@database/05_reports.sql
```

The short demonstration creates a normal `$1,000` transfer and a high-value `$60,000` transfer, prints the resulting states, commits both, and displays the reports:

```sql
@database/06_demo.sql
```

`08_reset.sql` clears demo transfer, review and audit history and restores seed balances/configuration only after an explicit `YES` response. Use it only in the disposable classroom schema.

## Start the optional Flask dashboard

From PowerShell in the repository directory:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Edit `.env` with the Oracle service, a database username/password, a random `FLASK_SECRET_KEY`, and the displayed reviewer name. Keep `.env` private; it is ignored by Git. Then start the dashboard:

```powershell
python .\app\app.py
```

Open [http://127.0.0.1:5000](http://127.0.0.1:5000). The default app binds to loopback. The app has no sign-in system, so use it only in a local classroom environment with a restricted Oracle account. Oracle connection and package execution must be tested against your instance. See [security and limitations](docs/SECURITY_AND_LIMITATIONS.md).

## Demonstration flow

1. Use the default `FLAG_AND_COMPLETE` mode and create a transfer of `1000.00`; confirm `COMPLETED` and the account balance movement.
2. Create a transfer of `60000.00`; at the seeded `50000.00` threshold it completes with `risk_flag = Y` and a pending review item.
3. Change `TRANSFER_MODE` to `HOLD_FOR_REVIEW` in SQL, create another high-value transfer, and confirm balances stay unchanged.
4. Approve it through the dashboard or `PKG_LEDGERLENS.REVIEW_TRANSFER`; execution rechecks the account status and available funds.
5. Run the report and audit queries to explain the lifecycle.

The detailed five-minute narration is in [the demo script](docs/DEMO_SCRIPT.md).

## Test and Validation Record

### Oracle Live SQL validation

The following validation was completed using Oracle Live SQL:

- Database schema and seed data were created successfully.
- `PKG_LEDGERLENS` package body compiled with no reported errors.
- `trg_transfers_status_audit` trigger compiled with no reported errors.
- The demonstration successfully completed a normal $1,000 transfer and a high-value $60,000 transfer. The high-value transfer was marked with `risk_flag = Y`.
- The PL/SQL test suite reported **17 PASS, 0 FAIL**.

The test suite covered normal transfers, high-value classification, review workflows, insufficient funds, invalid amounts, inactive accounts, audit records, duplicate review prevention, rollback behavior, and repeated-processing protection.

### Limitations

- Oracle Live SQL restricts certain SQL*Plus commands, including `WHENEVER SQLERROR` and script-invocation commands such as `@@filename.sql`.
- The concurrent two-session test requires a live Oracle instance and has not been demonstrated by the single-session test run.
- The local Flask dashboard's connection to Oracle has not yet been verified.
- These results demonstrate educational test coverage; they do not establish production readiness or certified fraud detection.

## Student report, ER model and viva

- [Project report](docs/PROJECT_REPORT.md) includes an editable title-page template and the requested report sections.
- [ER diagram](docs/ER_DIAGRAM.md) contains Mermaid source.
- [Viva questions](docs/VIVA_QUESTIONS.md) includes beginner-friendly answers.
- [Architecture](docs/ARCHITECTURE.md) and [database design](docs/DATABASE_DESIGN.md) explain object responsibilities.

## Publish to GitHub

Review `.env` and `git status` first; do not stage secrets or real customer data. Then:

```powershell
git init
git add .
git commit -m "Build LedgerLens Oracle transaction monitoring project"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/LedgerLens.git
git push -u origin main
```

Create the empty GitHub repository before setting `origin`, or follow the [GitHub guide](docs/GITHUB_GUIDE.md). Replace the placeholder username and repository URL with your own.

## License

MIT License. See [LICENSE](LICENSE).
