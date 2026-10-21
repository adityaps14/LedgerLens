"""Local classroom dashboard for LedgerLens. Run with: python app.py"""
from __future__ import annotations

import hmac
import os
import secrets
from decimal import Decimal, InvalidOperation
from pathlib import Path

from flask import Flask, abort, flash, redirect, render_template, request, session, url_for
try:
    from dotenv import load_dotenv
except ImportError:  # Minimal fallback keeps local setup useful before pip install.
    def load_dotenv(path: Path) -> None:
        if not path.exists():
            return
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            value = value.strip().strip("\"'")
            os.environ.setdefault(key.strip(), value)

import db

load_dotenv(Path(__file__).resolve().parents[1] / ".env")
app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY") or secrets.token_hex(32)
app.config["MAX_CONTENT_LENGTH"] = 16 * 1024


@app.before_request
def protect_post_forms() -> None:
    if request.method == "POST":
        expected = session.get("csrf_token", "")
        supplied = request.form.get("csrf_token", "")
        if not expected or not hmac.compare_digest(expected, supplied):
            abort(400, description="The form expired. Reload the page and try again.")


@app.context_processor
def inject_csrf_token() -> dict[str, str]:
    if "csrf_token" not in session:
        session["csrf_token"] = secrets.token_urlsafe(32)
    return {"csrf_token": session["csrf_token"]}


def database_error_message(exc: Exception) -> str:
    if isinstance(exc, db.DatabaseConfigurationError):
        return str(exc)
    return "Oracle operation failed. Check the database connection and Oracle error details in the server console."


def safe_database_page(template: str, **context):
    try:
        return render_template(template, **context)
    except Exception as exc:
        return render_template("error.html", message=database_error_message(exc)), 503


def parse_positive_id(raw: str, field_name: str) -> int:
    try:
        value = int(raw)
        if value < 1:
            raise ValueError
        return value
    except (TypeError, ValueError):
        raise ValueError(f"{field_name} must be a positive account ID.") from None


def parse_amount(raw: str) -> Decimal:
    try:
        amount = Decimal(raw)
    except (InvalidOperation, TypeError):
        raise ValueError("Enter a valid amount.") from None
    if not amount.is_finite() or amount <= 0:
        raise ValueError("Amount must be greater than zero.")
    if amount.as_tuple().exponent < -2:
        raise ValueError("Amount may have no more than two decimal places.")
    return amount


@app.get("/")
def index():
    try:
        data = db.dashboard_data()
        return render_template("index.html", **data)
    except Exception as exc:
        return render_template("error.html", message=database_error_message(exc)), 503


@app.route("/transfers/new", methods=["GET", "POST"])
def new_transfer():
    if request.method == "POST":
        try:
            from_id = parse_positive_id(request.form.get("from_account_id"), "Source account")
            to_id = parse_positive_id(request.form.get("to_account_id"), "Destination account")
            amount = parse_amount(request.form.get("amount", ""))
            result = db.create_transfer(from_id, to_id, amount)
            if result["status"] in ("COMPLETED", "HELD_FOR_REVIEW"):
                flash(f"Transfer {result['reference']} is {result['status']}.", "success")
            else:
                flash(result.get("error") or f"Transfer ended with status {result['status']}.", "error")
            if result.get("transfer_id"):
                return redirect(url_for("transfer_detail", transfer_id=int(result["transfer_id"])))
            return redirect(url_for("new_transfer"))
        except Exception as exc:
            flash(str(exc) if isinstance(exc, ValueError) else database_error_message(exc), "error")
    try:
        return render_template("new_transfer.html", accounts=db.accounts())
    except Exception as exc:
        return render_template("error.html", message=database_error_message(exc)), 503


@app.get("/transfers/<int:transfer_id>")
def transfer_detail(transfer_id: int):
    try:
        transfer = db.transfer_detail(transfer_id)
        if transfer is None:
            abort(404)
        return render_template("transfer_detail.html", transfer=transfer)
    except Exception as exc:
        if getattr(exc, "code", None) == 404:
            raise
        return render_template("error.html", message=database_error_message(exc)), 503


@app.get("/reviews")
def reviews():
    try:
        return render_template("reviews.html", reviews=db.review_queue(),
                               reviewer=os.getenv("LEDGERLENS_REVIEWER", "Classroom Reviewer"))
    except Exception as exc:
        return render_template("error.html", message=database_error_message(exc)), 503


@app.post("/reviews/<int:transfer_id>/<decision>")
def decide_review(transfer_id: int, decision: str):
    decision = decision.upper()
    if decision not in ("APPROVED", "REJECTED"):
        abort(404)
    reviewer = (request.form.get("reviewer") or os.getenv("LEDGERLENS_REVIEWER") or "").strip()
    notes = request.form.get("notes", "").strip() or None
    try:
        result = db.review_transfer(transfer_id, decision, reviewer, notes)
        if result["status"] == "COMPLETED" or result["status"] == "REJECTED":
            flash(f"{decision.title()} recorded. Transfer status: {result['status']}.", "success")
        else:
            flash(result.get("error") or f"Review ended with status {result['status']}.", "error")
    except Exception as exc:
        flash(database_error_message(exc), "error")
    return redirect(url_for("reviews"))


@app.route("/settings", methods=["GET", "POST"])
def settings():
    if request.method == "POST":
        try:
            amount = parse_amount(request.form.get("threshold", ""))
            db.set_threshold(amount)
            flash("High-value threshold updated and recorded in configuration audit.", "success")
            return redirect(url_for("settings"))
        except Exception as exc:
            flash(str(exc) if isinstance(exc, ValueError) else database_error_message(exc), "error")
    try:
        return render_template("settings.html", settings=db.get_settings(), history=db.threshold_history())
    except Exception as exc:
        return render_template("error.html", message=database_error_message(exc)), 503


@app.errorhandler(400)
def bad_request(error):
    return render_template("error.html", message=getattr(error, "description", "Bad request.")), 400


@app.errorhandler(404)
def not_found(error):
    return render_template("error.html", message="That page or transfer was not found."), 404


if __name__ == "__main__":
    # Bind to loopback: this educational app has no sign-in or reviewer identity service.
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", "5000")), debug=False)
