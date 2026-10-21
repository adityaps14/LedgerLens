"""Small Oracle data-access layer. Business rules live in PKG_LEDGERLENS."""
from __future__ import annotations

import os
from decimal import Decimal
from typing import Any

try:
    import oracledb
except ImportError:  # Keep the UI importable so it can show setup guidance before driver install.
    oracledb = None


class DatabaseConfigurationError(RuntimeError):
    """Raised when Oracle connection settings are missing."""


def connect() -> oracledb.Connection:
    user = os.getenv("ORACLE_USER")
    password = os.getenv("ORACLE_PASSWORD")
    dsn = os.getenv("ORACLE_DSN")
    missing = [name for name, value in (
        ("ORACLE_USER", user), ("ORACLE_PASSWORD", password), ("ORACLE_DSN", dsn)
    ) if not value]
    if missing:
        raise DatabaseConfigurationError("Set these environment variables: " + ", ".join(missing))
    if oracledb is None:
        raise DatabaseConfigurationError("Install the project requirements to add python-oracledb.")
    return oracledb.connect(user=user, password=password, dsn=dsn)


def query_all(sql: str, binds: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    connection = connect()
    try:
        with connection.cursor() as cursor:
            cursor.execute(sql, binds or {})
            names = [column[0].lower() for column in cursor.description]
            return [dict(zip(names, row)) for row in cursor.fetchall()]
    finally:
        connection.close()


def query_one(sql: str, binds: dict[str, Any] | None = None) -> dict[str, Any] | None:
    rows = query_all(sql, binds)
    return rows[0] if rows else None


def dashboard_data() -> dict[str, Any]:
    summary = query_one("""
        SELECT COUNT(*) AS transfer_count,
               NVL(SUM(CASE WHEN status = 'COMPLETED' THEN amount END), 0) AS completed_value,
               NVL(SUM(CASE WHEN status = 'HELD_FOR_REVIEW' THEN 1 ELSE 0 END), 0) AS held_count,
               NVL(SUM(CASE WHEN risk_flag = 'Y' THEN 1 ELSE 0 END), 0) AS flagged_count
          FROM transfers
    """) or {}
    balances = query_all("""
        SELECT a.account_number, c.full_name AS account_holder, a.account_type,
               a.balance, a.account_status
          FROM accounts a JOIN customers c ON c.customer_id = a.customer_id
         ORDER BY a.account_number
    """)
    recent = query_all("""
        SELECT t.transfer_id, t.reference_number, fa.account_number AS from_account,
               ta.account_number AS to_account, t.amount, t.status, t.risk_flag, t.created_at
          FROM transfers t JOIN accounts fa ON fa.account_id = t.from_account_id
          JOIN accounts ta ON ta.account_id = t.to_account_id
         ORDER BY t.created_at DESC FETCH FIRST 10 ROWS ONLY
    """)
    alerts = query_all("""
        SELECT transfer_id, reference_number, amount, risk_reason, status, created_at
          FROM transfers WHERE risk_flag = 'Y'
         ORDER BY created_at DESC FETCH FIRST 5 ROWS ONLY
    """)
    pending = query_all("""
        SELECT r.review_id, t.transfer_id, t.reference_number, t.amount,
               r.reason, r.created_at
          FROM review_queue r JOIN transfers t ON t.transfer_id = r.transfer_id
         WHERE r.review_status = 'PENDING' ORDER BY r.created_at
    """)
    return {"summary": summary, "balances": balances, "recent": recent,
            "alerts": alerts, "pending": pending}


def accounts() -> list[dict[str, Any]]:
    return query_all("""
        SELECT account_id, account_number, account_type, balance, account_status
          FROM accounts ORDER BY account_number
    """)


def create_transfer(from_account_id: int, to_account_id: int, amount: Decimal) -> dict[str, Any]:
    connection = connect()
    try:
        with connection.cursor() as cursor:
            transfer_id = cursor.var(oracledb.DB_TYPE_NUMBER)
            reference = cursor.var(oracledb.DB_TYPE_VARCHAR, size=40)
            status = cursor.var(oracledb.DB_TYPE_VARCHAR, size=24)
            risk = cursor.var(oracledb.DB_TYPE_CHAR, size=1)
            error = cursor.var(oracledb.DB_TYPE_VARCHAR, size=1000)
            cursor.execute("""
                BEGIN
                    pkg_ledgerlens.create_transfer(
                        :from_id, :to_id, :amount,
                        :transfer_id, :reference, :status, :risk, :error_message
                    );
                END;
            """, {
                "from_id": from_account_id,
                "to_id": to_account_id,
                "amount": amount,
                "transfer_id": transfer_id,
                "reference": reference,
                "status": status,
                "risk": risk,
                "error_message": error,
            })
            connection.commit()
            return {"transfer_id": transfer_id.getvalue(), "reference": reference.getvalue(),
                    "status": status.getvalue(), "risk_flag": risk.getvalue(),
                    "error": error.getvalue()}
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def review_transfer(transfer_id: int, decision: str, reviewer: str, notes: str | None) -> dict[str, Any]:
    connection = connect()
    try:
        with connection.cursor() as cursor:
            status = cursor.var(oracledb.DB_TYPE_VARCHAR, size=24)
            error = cursor.var(oracledb.DB_TYPE_VARCHAR, size=1000)
            cursor.execute("""
                BEGIN
                    pkg_ledgerlens.review_transfer(
                        :transfer_id, :decision, :reviewer, :notes, :status, :error_message
                    );
                END;
            """, {"transfer_id": transfer_id, "decision": decision,
                  "reviewer": reviewer, "notes": notes, "status": status,
                  "error_message": error})
            connection.commit()
            return {"status": status.getvalue(), "error": error.getvalue()}
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def transfer_detail(transfer_id: int) -> dict[str, Any] | None:
    transfer = query_one("""
        SELECT t.transfer_id, t.reference_number, t.from_account_id, t.to_account_id,
               fa.account_number AS from_account, fc.full_name AS sender,
               ta.account_number AS to_account, tc.full_name AS receiver,
               t.amount, t.status, t.risk_flag, t.risk_reason, t.created_at, t.completed_at
          FROM transfers t JOIN accounts fa ON fa.account_id = t.from_account_id
          JOIN customers fc ON fc.customer_id = fa.customer_id
          JOIN accounts ta ON ta.account_id = t.to_account_id
          JOIN customers tc ON tc.customer_id = ta.customer_id
         WHERE t.transfer_id = :transfer_id
    """, {"transfer_id": transfer_id})
    if transfer:
        transfer["audit"] = query_all("""
            SELECT action, old_status, new_status, details, created_at
              FROM audit_log WHERE transfer_id = :transfer_id
             ORDER BY created_at, audit_id
        """, {"transfer_id": transfer_id})
    return transfer


def review_queue() -> list[dict[str, Any]]:
    return query_all("""
        SELECT r.review_id, t.transfer_id, t.reference_number, t.amount,
               r.reason, r.created_at
          FROM review_queue r JOIN transfers t ON t.transfer_id = r.transfer_id
         WHERE r.review_status = 'PENDING' ORDER BY r.created_at
    """)


def get_settings() -> list[dict[str, Any]]:
    return query_all("""
        SELECT config_key, config_value, description, updated_at
          FROM system_config ORDER BY config_key
    """)


def threshold_history() -> list[dict[str, Any]]:
    return query_all("""
        SELECT config_audit_id, old_value, new_value, changed_by, changed_at
          FROM config_audit WHERE config_key = 'HIGH_VALUE_THRESHOLD'
         ORDER BY changed_at DESC FETCH FIRST 20 ROWS ONLY
    """)


def set_threshold(amount: Decimal) -> None:
    connection = connect()
    try:
        with connection.cursor() as cursor:
            cursor.execute("BEGIN pkg_ledgerlens.set_high_value_threshold(:amount); END;", {"amount": amount})
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()
