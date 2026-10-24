"""In-memory demo backend for LedgerLens.

All data is sample data held in this Python process. It is NOT persisted to Oracle
or to disk. Restarting the Flask app resets the demo data.
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal, InvalidOperation
from threading import RLock
from typing import Any
import itertools

_lock = RLock()
_next_transfer_id = itertools.count(1004)
_next_review_id = itertools.count(501)

_accounts = [
    {"account_id": 1, "account_number": "LL-10001", "account_type": "Current", "balance": Decimal("25000.00"), "account_status": "ACTIVE", "holder": "Aarav Sharma"},
    {"account_id": 2, "account_number": "LL-10002", "account_type": "Savings", "balance": Decimal("18000.00"), "account_status": "ACTIVE", "holder": "Meera Kapoor"},
    {"account_id": 3, "account_number": "LL-10003", "account_type": "Current", "balance": Decimal("82000.00"), "account_status": "ACTIVE", "holder": "Kabir Verma"},
    {"account_id": 4, "account_number": "LL-10004", "account_type": "Savings", "balance": Decimal("7500.00"), "account_status": "ACTIVE", "holder": "Ananya Singh"},
]
_threshold = Decimal("50000.00")
_transfers: list[dict[str, Any]] = [
    {"transfer_id": 1001, "reference_number": "LL-DEMO-1001", "from_account_id": 1, "to_account_id": 2, "from_account": "LL-10001", "sender": "Aarav Sharma", "to_account": "LL-10002", "receiver": "Meera Kapoor", "amount": Decimal("2500.00"), "status": "COMPLETED", "risk_flag": "N", "risk_reason": None, "created_at": "2026-10-22 10:15:00", "completed_at": "2026-10-22 10:15:01", "audit": [{"action": "TRANSFER_CREATED", "old_status": None, "new_status": "COMPLETED", "details": "Demo transfer completed", "created_at": "2026-10-22 10:15:01"}]},
    {"transfer_id": 1002, "reference_number": "LL-DEMO-1002", "from_account_id": 3, "to_account_id": 4, "from_account": "LL-10003", "sender": "Kabir Verma", "to_account": "LL-10004", "receiver": "Ananya Singh", "amount": Decimal("65000.00"), "status": "PENDING_REVIEW", "risk_flag": "Y", "risk_reason": "Amount exceeds review threshold", "created_at": "2026-10-22 11:05:00", "completed_at": None, "audit": [{"action": "TRANSFER_CREATED", "old_status": None, "new_status": "PENDING_REVIEW", "details": "Flagged because amount exceeded demo threshold", "created_at": "2026-10-22 11:05:00"}]},
    {"transfer_id": 1003, "reference_number": "LL-DEMO-1003", "from_account_id": 2, "to_account_id": 1, "from_account": "LL-10002", "sender": "Meera Kapoor", "to_account": "LL-10001", "receiver": "Aarav Sharma", "amount": Decimal("1200.00"), "status": "COMPLETED", "risk_flag": "N", "risk_reason": None, "created_at": "2026-10-22 12:30:00", "completed_at": "2026-10-22 12:30:01", "audit": [{"action": "TRANSFER_CREATED", "old_status": None, "new_status": "COMPLETED", "details": "Demo transfer completed", "created_at": "2026-10-22 12:30:01"}]},
]
_settings_history: list[dict[str, Any]] = [
    {"config_audit_id": 1, "old_value": None, "new_value": "50000.00", "changed_by": "system", "changed_at": "2026-10-22 09:00:00"}
]

def _now() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def _account(account_id: int) -> dict[str, Any] | None:
    return next((a for a in _accounts if a["account_id"] == int(account_id)), None)

def _money(value: Any) -> Decimal:
    try:
        amount = Decimal(str(value)).quantize(Decimal("0.01"))
    except (InvalidOperation, ValueError, TypeError):
        raise ValueError("Enter a valid amount.")
    if not amount.is_finite() or amount <= 0:
        raise ValueError("Amount must be greater than zero.")
    return amount

def accounts():
    with _lock:
        return [{k: a[k] for k in ("account_id", "account_number", "account_type", "balance", "account_status")} | {"holder": a["holder"]} for a in _accounts]

def dashboard_data():
    with _lock:
        completed = sum(
            1 for t in _transfers if t["status"] == "COMPLETED"
        )
        pending_count = sum(
            1 for t in _transfers if t["status"] == "PENDING_REVIEW"
        )
        flagged = sum(
            1 for t in _transfers if t["risk_flag"] == "Y"
        )

        total_amount = sum(
            (t["amount"] for t in _transfers), Decimal("0.00")
        )

        recent = sorted(
            _transfers,
            key=lambda t: t["transfer_id"],
            reverse=True
        )[:8]

        balances = [
            {
                "account_number": a["account_number"],
                "account_type": a["account_type"],
                "account_holder": a["holder"],
                "balance": a["balance"],
                "account_status": a["account_status"],
            }
            for a in _accounts
        ]

        alerts = [
            {
                "transfer_id": t["transfer_id"],
                "reference_number": t["reference_number"],
                "amount": t["amount"],
                "risk_reason": t["risk_reason"],
                "reason": t["risk_reason"] or "Flagged transfer",
                "status": t["status"],
                "created_at": t["created_at"],
            }
            for t in _transfers
            if t["risk_flag"] == "Y"
        ]

        pending = [
            {
                "transfer_id": t["transfer_id"],
                "reference_number": t["reference_number"],
                "amount": t["amount"],
                "reason": t["risk_reason"] or "Flagged transfer",
                "created_at": t["created_at"],
            }
            for t in _transfers
            if t["status"] == "PENDING_REVIEW"
        ]

        summary = {
            "account_count": len(_accounts),
            "total_accounts": len(_accounts),
            "transfer_count": len(_transfers),
            "total_transfers": len(_transfers),
            "completed_count": completed,
            "completed_transfers": completed,
            "pending_count": pending_count,
            "pending_reviews": pending_count,
            "held_count": pending_count,
            "flagged_count": flagged,
            "flagged_transfers": flagged,
            "total_amount": total_amount,
            "total_balance": sum(
                (a["balance"] for a in _accounts), Decimal("0.00")
            ),
            "completed_value": sum(
                (t["amount"] for t in _transfers
                 if t["status"] == "COMPLETED"),
                Decimal("0.00")
            ),
        }

        return {
            "summary": summary,
            "balances": balances,
            "recent": [dict(t) for t in recent],
            "alerts": alerts,
            "pending": pending,
        }

def create_transfer(from_account_id, to_account_id, amount):
    with _lock:
        try:
            src_id, dst_id = int(from_account_id), int(to_account_id)
            value = _money(amount)
        except (ValueError, TypeError) as exc:
            return {"transfer_id": None, "reference": None, "status": "ERROR", "risk_flag": "N", "error": str(exc)}
        src, dst = _account(src_id), _account(dst_id)
        if not src or not dst:
            return {"transfer_id": None, "reference": None, "status": "ERROR", "risk_flag": "N", "error": "Select valid sender and receiver accounts."}
        if src_id == dst_id:
            return {"transfer_id": None, "reference": None, "status": "ERROR", "risk_flag": "N", "error": "Sender and receiver must be different accounts."}
        if src["account_status"] != "ACTIVE" or dst["account_status"] != "ACTIVE":
            return {"transfer_id": None, "reference": None, "status": "ERROR", "risk_flag": "N", "error": "Both accounts must be active."}
        if src["balance"] < value:
            return {"transfer_id": None, "reference": None, "status": "ERROR", "risk_flag": "N", "error": "Insufficient sample balance."}
        tid = next(_next_transfer_id)
        ref = f"LL-DEMO-{tid}"
        now = _now()
        flagged = value >= _threshold
        status = "PENDING_REVIEW" if flagged else "COMPLETED"
        transfer = {"transfer_id": tid, "reference_number": ref, "from_account_id": src_id, "to_account_id": dst_id, "from_account": src["account_number"], "sender": src["holder"], "to_account": dst["account_number"], "receiver": dst["holder"], "amount": value, "status": status, "risk_flag": "Y" if flagged else "N", "risk_reason": f"Amount meets/exceeds review threshold ({_threshold})" if flagged else None, "created_at": now, "completed_at": None if flagged else now, "audit": [{"action": "TRANSFER_CREATED", "old_status": None, "new_status": status, "details": "Demo transfer created; " + ("flagged for manual review" if flagged else "completed in demo mode"), "created_at": now}]}
        _transfers.append(transfer)
        if not flagged:
            src["balance"] -= value
            dst["balance"] += value
        else:
            transfer["review_id"] = next(_next_review_id)
        return {"transfer_id": tid, "reference": ref, "status": status, "risk_flag": "Y" if flagged else "N", "error": None}

def transfer_detail(transfer_id):
    with _lock:
        t = next((x for x in _transfers if x["transfer_id"] == int(transfer_id)), None)
        return dict(t) if t else None

def review_queue():
    with _lock:
        return [{"review_id": t.get("review_id", t["transfer_id"]), "transfer_id": t["transfer_id"], "reference_number": t["reference_number"], "amount": t["amount"], "reason": t["risk_reason"] or "Flagged transfer", "created_at": t["created_at"]} for t in _transfers if t["status"] == "PENDING_REVIEW"]

def review_transfer(transfer_id, decision, reviewer, notes=""):
    with _lock:
        t = next((x for x in _transfers if x["transfer_id"] == int(transfer_id)), None)
        if not t:
            return {"status": "ERROR", "error": "Transfer not found in demo data."}
        if t["status"] != "PENDING_REVIEW":
            return {"status": "ERROR", "error": "This transfer is not waiting for review."}
        decision = str(decision).lower()
        if decision not in ("approve", "reject"):
            return {"status": "ERROR", "error": "Decision must be approve or reject."}
        old = t["status"]
        src, dst = _account(t["from_account_id"]), _account(t["to_account_id"])
        now = _now()
        if decision == "approve":
            if not src or src["balance"] < t["amount"]:
                return {"status": "ERROR", "error": "Insufficient sample balance to approve this transfer."}
            src["balance"] -= t["amount"]
            dst["balance"] += t["amount"]
            t["status"] = "COMPLETED"
            t["completed_at"] = now
            action = "REVIEW_APPROVED"
        else:
            t["status"] = "REJECTED"
            action = "REVIEW_REJECTED"
        t["audit"].append({"action": action, "old_status": old, "new_status": t["status"], "details": f"Reviewer: {reviewer or 'demo reviewer'}. Notes: {notes or '—'}", "created_at": now})
        return {"status": t["status"], "error": None}

def get_settings():
    with _lock:
        return [{"config_key": "TRANSFER_REVIEW_THRESHOLD", "config_value": str(_threshold), "description": "Transfers at or above this amount require manual review (demo only).", "updated_at": _settings_history[-1]["changed_at"]}]

def threshold_history():
    with _lock:
        return [dict(x) for x in reversed(_settings_history)]

def set_threshold(amount):
    global _threshold
    with _lock:
        try:
            value = _money(amount)
        except ValueError as exc:
            return {"status": "ERROR", "error": str(exc)}
        old = _threshold
        _threshold = value
        _settings_history.append({"config_audit_id": len(_settings_history) + 1, "old_value": str(old), "new_value": str(value), "changed_by": "demo user", "changed_at": _now()})
        return {"status": "SUCCESS", "error": None}
