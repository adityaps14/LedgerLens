from decimal import Decimal
from app import demo_db


def test_accounts_are_available():
    accounts = demo_db.accounts()
    assert len(accounts) >= 2
    assert all("account_number" in account for account in accounts)


def test_dashboard_has_required_summary():
    dashboard = demo_db.dashboard_data()
    assert "summary" in dashboard
    assert "balances" in dashboard
    assert "recent" in dashboard
    assert dashboard["summary"]["account_count"] >= 2


def test_invalid_amount_is_rejected():
    result = demo_db.create_transfer(1, 2, 0)
    assert result["status"] == "ERROR"
    assert result["error"] is not None


def test_same_sender_and_receiver_is_rejected():
    result = demo_db.create_transfer(1, 1, 100)
    assert result["status"] == "ERROR"
    assert "different accounts" in result["error"]


def test_threshold_is_positive():
    settings = demo_db.get_settings()
    assert len(settings) > 0
    assert Decimal(settings[0]["config_value"]) > 0


def test_high_value_transfer_requires_review():
    result = demo_db.create_transfer(3, 4, 60000)
    assert result["status"] == "PENDING_REVIEW"
    assert result["risk_flag"] == "Y"
    assert result["error"] is None
