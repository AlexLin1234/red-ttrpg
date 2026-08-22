"""The hosted campaign API: month-end billing, undo/redo, and bad state files.

The API reads one JSON file named by an environment variable, so every test gets
its own file in a temporary directory and the module is reloaded to pick it up.
Nothing here touches a real deployment's state.

The fixtures live in this file rather than a conftest: the assistant suite
already has one, and two same-named conftest modules in a rootdir without
packages shadow each other.
"""

from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path

import pytest
from starlette.websockets import WebSocketDisconnect

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))


@pytest.fixture
def api(tmp_path, monkeypatch):
    """The client, the module, a `write` for the state file, and its path."""

    from fastapi.testclient import TestClient

    state_path = tmp_path / "campaign.json"
    monkeypatch.setenv("REDLINE_STATE", str(state_path))
    import service.app as app_module

    importlib.reload(app_module)
    app_module.clients.clear()

    def write(state: object) -> None:
        state_path.write_text(state if isinstance(state, str) else json.dumps(state))

    with TestClient(app_module.app) as client:
        yield client, app_module, write, state_path


@pytest.fixture
def roster() -> dict:
    return {
        "current_month": "2045-01",
        "characters": [
            {"id": "spike", "name": "Spike", "lifestyle": "kibble", "cash": 500},
            {"id": "mira", "name": "Mira", "lifestyle": "fresh_food", "cash": 10},
        ],
    }


def test_a_month_end_bills_every_lifestyle_and_warns_on_the_ones_that_bounce(api, roster):
    client, _module, write, _path = api
    write(roster)

    response = client.post("/encounter/month-end", json={"month": "2045-01"})

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["closed_month"] == "2045-01"
    assert body["new_month"] == "2045-02"
    assert body["total_deducted"] == 100
    assert [result["status"] for result in body["results"]] == ["paid", "unpaid"]
    assert len(body["warnings"]) == 1


def test_the_same_month_cannot_be_closed_twice(api, roster):
    client, _module, write, _path = api
    write(roster)

    assert client.post("/encounter/month-end", json={"month": "2045-01"}).status_code == 200
    repeated = client.post("/encounter/month-end", json={"month": "2045-01"})

    assert repeated.status_code == 409


def test_undo_puts_the_month_back_and_redo_bills_it_again(api, roster):
    client, _module, write, _path = api
    write(roster)
    client.post("/encounter/month-end", json={"month": "2045-01"})

    undone = client.post("/encounter/month-end/undo")
    assert undone.status_code == 200
    assert undone.json()["current_month"] == "2045-01"
    assert undone.json()["characters"][0]["cash"] == 500

    redone = client.post("/encounter/month-end/redo")
    assert redone.status_code == 200
    assert redone.json()["current_month"] == "2045-02"
    assert redone.json()["characters"][0]["cash"] == 400


@pytest.mark.parametrize(
    "state",
    [
        pytest.param("{not json", id="not json"),
        pytest.param([], id="not an object"),
        pytest.param({"current_month": 204501, "characters": []}, id="month is not a string"),
        pytest.param({"current_month": "2045-01", "characters": "nope"}, id="roster not a list"),
        pytest.param(
            {"current_month": "2045-01", "characters": [{"name": "A", "lifestyle": "kibble", "cash": 1}]},
            id="character without an id",
        ),
        pytest.param(
            {"current_month": "2045-01", "characters": [{"id": "a", "name": "A", "lifestyle": "kibble"}]},
            id="character without cash",
        ),
        pytest.param(
            {"current_month": "2045-01", "characters": [], "undo": "nope"},
            id="undo history not a list",
        ),
    ],
)
def test_a_malformed_state_file_is_reported_rather_than_crashing(api, state):
    """Every key the roll indexes directly is checked before it is indexed."""

    client, _module, write, _path = api
    write(state)

    response = client.post("/encounter/month-end", json={"month": "2045-01"})

    assert response.status_code == 422, response.text
    assert response.json()["detail"]


def test_a_missing_state_file_is_reported_rather_than_crashing(api):
    client, _module, _write, _path = api

    assert client.post("/encounter/month-end", json={"month": "2045-01"}).status_code == 422


def test_a_state_file_with_no_roster_still_closes_the_month(api):
    client, _module, write, _path = api
    write({"current_month": "2045-01"})

    response = client.post("/encounter/month-end", json={"month": "2045-01"})

    assert response.status_code == 200
    assert response.json()["results"] == []


def test_a_listener_is_registered_and_dropped_around_its_connection(api, roster):
    client, module, write, _path = api
    write(roster)

    with client.websocket_connect("/ws") as socket:
        assert socket.receive_json()["type"] == "campaign_state"
        assert len(module.clients) == 1

    assert module.clients == set()


def test_a_socket_that_cannot_be_greeted_is_never_left_in_the_broadcast_set(api):
    """The greeting reads the state file, and reading it can fail.

    Registering before that send left a dead socket in `clients` forever, and
    every later broadcast paid for it.
    """

    client, module, write, _path = api
    write("{not json")

    # The server closes the socket instead of greeting it, which surfaces here
    # as a disconnect rather than a message.
    with pytest.raises(WebSocketDisconnect), client.websocket_connect("/ws") as socket:
        socket.receive_json()

    assert module.clients == set()
