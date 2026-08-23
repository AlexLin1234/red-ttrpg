"""The month-end close, checked against the same cases the GDScript suite runs.

The app and this service both close a campaign month, in two languages. They
read one table now (``data/lifestyle.json``), and this file and
``tests/test_lifestyle.gd`` both walk ``data/lifestyle_cases.json``, so a rule
change that reaches only one implementation fails rather than drifting quietly.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from service import app as service

CASES_PATH = Path(__file__).resolve().parent.parent.parent / "data" / "lifestyle_cases.json"
CASES = json.loads(CASES_PATH.read_text(encoding="utf-8"))


def _state(characters: list[dict], month: str) -> dict:
    return {
        "current_month": month,
        "closed_months": [],
        "characters": characters,
        "undo": [],
        "redo": [],
    }


def _character(case: dict) -> dict:
    entry = dict(case["character"])
    entry.setdefault("lifestyle_status", "paid")
    entry.setdefault("lifestyle_paid_through", None)
    entry.setdefault("lifestyle_balance_due", 0)
    entry.setdefault("lifestyle_grace_days", 0)
    entry.setdefault("last_lifestyle_charge", 0)
    return entry


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(service, "STATE_PATH", tmp_path / "campaign.json")
    return TestClient(service.app)


def _closing_month(billed: str) -> str:
    """The month whose close bills ``billed``."""

    year, month = (int(part) for part in billed.split("-"))
    return f"{year - 1:04d}-12" if month == 1 else f"{year:04d}-{month - 1:02d}"


def test_the_service_bills_the_same_way_the_app_does(client, tmp_path):
    billed = CASES["billed_month"]
    closing = _closing_month(billed)
    characters = [_character(case) for case in CASES["cases"]]
    service.save(_state(characters, closing))

    response = client.post("/encounter/month-end", json={"month": closing})
    assert response.status_code == 200, response.text

    after = {entry["id"]: entry for entry in json.loads(service.STATE_PATH.read_text())["characters"]}
    for case in CASES["cases"]:
        expected = case["expect"]
        actual = after[case["character"]["id"]]
        assert actual["cash"] == expected["cash"], case["name"]
        assert actual["lifestyle_status"] == expected["status"], case["name"]
        assert actual["lifestyle_balance_due"] == expected["balance_due"], case["name"]
        assert actual["lifestyle_grace_days"] == expected["grace_days"], case["name"]
        if expected["paid_through"] is not None:
            assert actual["lifestyle_paid_through"] == expected["paid_through"], case["name"]

    reported = {row["character_id"]: row for row in response.json()["results"]}
    for case in CASES["cases"]:
        expected = case["expect"]
        row = reported[case["character"]["id"]]
        assert row["deducted"] == expected["deducted"], case["name"]
        assert row["status"] == expected["status"], case["name"]


def test_the_table_the_service_bills_from_is_the_shared_one():
    document = json.loads(
        (CASES_PATH.parent / "lifestyle.json").read_text(encoding="utf-8")
    )
    costs = {str(row["key"]): int(row["cost"]) for row in document["catalog"]}
    assert service.LIFESTYLES == costs
    assert service.GRACE_DAYS == int(document["grace_days"])


def test_every_lifestyle_in_the_table_is_billable(client):
    """A key the table offers but the endpoint cannot charge is a broken save."""

    characters = [
        _character({"character": {"id": key, "name": key, "lifestyle": key, "cash": 100000}})
        for key in service.LIFESTYLES
    ]
    service.save(_state(characters, "2045-09"))
    response = client.post("/encounter/month-end", json={"month": "2045-09"})
    assert response.status_code == 200, response.text
    assert all(row["status"] == "paid" for row in response.json()["results"])
