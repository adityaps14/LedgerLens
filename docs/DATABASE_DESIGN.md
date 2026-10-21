# Database Design

## Entities and constraints

- **CUSTOMERS**: fictional customer identity, unique email, creation timestamp.
- **ACCOUNTS**: one customer may own multiple accounts; each account number is unique. Monetary balance is `NUMBER(18,2)` and constrained nonnegative. Account type and state use checked values.
- **TRANSFERS**: sender and recipient are foreign keys to accounts; reference is unique; amount must be positive; status and risk flag are constrained. A check constraint disallows identical account IDs.
- **AUDIT_LOG**: append-style lifecycle/status details tied to a transfer.
- **SYSTEM_CONFIG**: named values for the threshold, operating mode, and maximum transfer amount.
- **REVIEW_QUEUE**: decision state, reason and timestamps. A function-based unique index allows historical queue rows but limits a transfer to one pending item.
- **SYSTEM_OPERATORS**: database usernames permitted to change the threshold through the package. Seed data registers the schema owner; an operator must explicitly add other users.
- **SYSTEM_REVIEWERS**: database usernames permitted to decide held transfers. Seed data registers the schema owner; reviewer display labels are stored separately from the database identity.
- **CONFIG_AUDIT**: old/new values and session user for threshold changes.

Identity columns require Oracle 12c or newer; the documented baseline is Oracle 19c or newer. Setup scripts are for a fresh dedicated schema and do not silently drop existing objects.

## Key design decisions

1. Monetary values are fixed-precision `NUMBER`, never binary floating point.
2. Package operations own savepoints but do not commit. The caller owns the encompassing transaction.
3. A request with valid positive amount/account references but a business-rule failure is retained as `FAILED`; nonpositive values or unknown account IDs cannot satisfy schema constraints and return a failure without a transfer row.
4. High-value is inclusive: an amount equal to the configured threshold is flagged.
5. `MAX_TRANSFER_AMOUNT` is a separate validation limit. The threshold classifies a transfer; it does not reject it.
6. The `FLAG_AND_COMPLETE` mode queues review after successful execution. `HOLD_FOR_REVIEW` queues before execution and only an approval can reach the processor.

## Indexes

Unique constraints cover customer email, account number and transfer reference. Supporting indexes cover customer-to-account lookup, transfer dates/status/from/to, audit events by transfer and review status/date. The review function-based unique index enforces one pending review row even if two sessions attempt to queue it.

## Configuration

`HIGH_VALUE_THRESHOLD` is stored as a decimal string with two decimal places and read by `GET_HIGH_VALUE_THRESHOLD`. Missing, nonnumeric, zero or negative threshold configuration raises an application error. `SET_HIGH_VALUE_THRESHOLD` checks positive two-decimal input, confirms the session user in `SYSTEM_OPERATORS`, updates the row and adds a configuration audit record. It intentionally leaves commit/rollback to the caller.

`TRANSFER_MODE` is `FLAG_AND_COMPLETE` or `HOLD_FOR_REVIEW`. `MAX_TRANSFER_AMOUNT` supplies a separate upper bound. Configuration is seeded to threshold `50000.00`, mode `FLAG_AND_COMPLETE`, and maximum `250000.00`.
