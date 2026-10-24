"""LedgerLens Flask UI. Select DEMO_MODE=true for the in-memory demo backend."""
from __future__ import annotations

import hmac
import os
import secrets
from decimal import Decimal, InvalidOperation
from pathlib import Path

from flask import Flask, flash, redirect, render_template, request, session, url_for

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).resolve().parents[1] / ".env")
except ImportError:
    pass

if os.getenv("DEMO_MODE", "false").strip().lower() == "true":
    import demo_db as db
else:
    import db

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY") or secrets.token_hex(32)
app.config["DEMO_MODE"] = os.getenv("DEMO_MODE", "false").strip().lower() == "true"

def database_error_message(exc):
    if app.config["DEMO_MODE"]:
        return f"Demo mode error: {exc}"
    message = str(exc)
    if "ORACLE_USER" in message or "ORACLE_PASSWORD" in message or "ORACLE_DSN" in message:
        return "Oracle connection settings are missing. Check your .env file, or set DEMO_MODE=true."
    return "Could not connect to Oracle. Check that the database is running and .env settings are correct."



@app.before_request
def ensure_csrf_token():
    session.setdefault("_csrf_token", secrets.token_urlsafe(32))


def csrf_token():
    return session.get("_csrf_token", "")


app.jinja_env.globals["csrf_token"] = csrf_token


@app.before_request
def verify_csrf():
    if request.method == "POST":
        sent = request.form.get("csrf_token", "")
        expected = session.get("_csrf_token", "")
        if not sent or not expected or not hmac.compare_digest(sent, expected):
            flash("Security token expired. Please try again.", "error")
            return redirect(request.referrer or url_for("index"))

@app.context_processor
def inject_mode():
    return {"demo_mode": app.config["DEMO_MODE"]}

@app.route("/")
def index():
    try:
        data = db.dashboard_data()
        return render_template("index.html", **data)
    except Exception as exc:
        return render_template("error.html", message=database_error_message(exc)), 503

@app.route("/transfers/new", methods=["GET", "POST"])
def new_transfer():
    if request.method == "POST":
        result = db.create_transfer(
            request.form.get("from_account_id"),
            request.form.get("to_account_id"),
            request.form.get("amount"),
        )
        if result.get("error"):
            flash(result["error"], "error")
            return redirect(url_for("new_transfer"))
        flash(f"Transfer {result.get('reference') or ''} created: {result.get('status')}.", "success")
        if result.get("transfer_id"):
            return redirect(url_for("transfer_detail", transfer_id=result["transfer_id"]))
        return redirect(url_for("new_transfer"))
    try:
        return render_template("new_transfer.html", accounts=db.accounts())
    except Exception as exc:
        return render_template("error.html", message=database_error_message(exc)), 503

@app.route("/transfers/<int:transfer_id>")
def transfer_detail(transfer_id):
    try:
        transfer = db.transfer_detail(transfer_id)
        if not transfer:
            flash("Transfer not found.", "error")
            return redirect(url_for("index"))
        return render_template("transfer_detail.html", transfer=transfer, detail=transfer)
    except Exception as exc:
        return render_template("error.html", message=database_error_message(exc)), 503

@app.route("/reviews")
def reviews():
    try:
        return render_template("reviews.html", reviews=db.review_queue(), queue=db.review_queue(), reviewer=request.args.get("reviewer", "demo reviewer"))
    except Exception as exc:
        return render_template("error.html", message=database_error_message(exc)), 503

@app.route("/reviews/<int:transfer_id>/<decision>", methods=["POST"])
def review(transfer_id, decision):
    result = db.review_transfer(transfer_id, decision, request.form.get("reviewer", "demo reviewer"), request.form.get("notes", ""))
    if result.get("error"):
        flash(result["error"], "error")
    else:
        flash(f"Review completed: {result.get('status')}.", "success")
    return redirect(url_for("reviews"))

@app.route("/settings", methods=["GET", "POST"])
def settings():
    if request.method == "POST":
        result = db.set_threshold(request.form.get("amount", request.form.get("config_value", "")))
        if isinstance(result, dict) and result.get("error"):
            flash(result["error"], "error")
        else:
            flash("Threshold updated." if not isinstance(result, dict) or result.get("status") != "ERROR" else result.get("error"), "success")
        return redirect(url_for("settings"))
    try:
        return render_template("settings.html", settings=db.get_settings(), history=db.threshold_history(), threshold_history=db.threshold_history())
    except Exception as exc:
        return render_template("error.html", message=database_error_message(exc)), 503

@app.errorhandler(404)
def not_found(_error):
    return render_template("error.html", message="Page not found."), 404

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", "5000")), debug=False)
