from __future__ import annotations

from fastapi.testclient import TestClient

from cprtool.gm.encounter import Encounter
from cprtool.gm.service import create_app
from test_encounter import FakeTables, FixedRng


ACTORS = {
    "solo": {
        "name": "Rache",
        "max_hp": 40,
        "attack_base": 12,
        "weapons": {"Heavy Pistol": {"ammo": 8, "weapon_type": "pistol", "damage_dice": 3, "magazine": 8}},
    },
    "goon": {"name": "Booster", "max_hp": 40, "hp": 30, "armor": {"body": 7, "head": 7}, "weapons": {}},
}

ATTACK = {"attacker_id": "solo", "target_id": "goon", "weapon": "Heavy Pistol", "distance_m": 5}


def client(*rolls: int) -> TestClient:
    encounter = Encounter(FakeTables(), rng=FixedRng(*rolls))
    return TestClient(create_app(encounter=encounter))


def actor(snapshot, actor_id: str):
    return next(entry for entry in snapshot["actors"] if entry["id"] == actor_id)


def test_encounter_round_trip_over_http():
    with client(8, 4, 4, 4) as http:
        loaded = http.post("/encounter", json={"actors": ACTORS})
        assert loaded.status_code == 200
        assert actor(loaded.json(), "goon")["hp"] == 30

        resolved = http.post("/encounter/attack", json=ATTACK).json()
        assert actor(resolved, "goon")["hp"] == 25
        assert resolved["card"]["title"] == "HIT"
        assert resolved["revision"] > loaded.json()["revision"]

        assert actor(http.post("/encounter/undo").json(), "goon")["hp"] == 30
        assert actor(http.post("/encounter/redo").json(), "goon")["hp"] == 25
        assert actor(http.get("/encounter").json(), "goon")["hp"] == 25


def test_the_viewer_socket_receives_the_current_state_then_every_change():
    with client(8, 4, 4, 4) as http:
        http.post("/encounter", json={"actors": ACTORS})
        with http.websocket_connect("/viewer") as socket:
            opening = socket.receive_json()
            assert opening["type"] == "snapshot"
            assert actor(opening, "goon")["hp"] == 30
            assert opening["card"] is None

            http.post("/encounter/attack", json=ATTACK)
            pushed = socket.receive_json()
            assert actor(pushed, "goon")["hp"] == 25
            assert pushed["card"]["lines"]

            http.post("/encounter/undo")
            assert actor(socket.receive_json(), "goon")["hp"] == 30


def test_rejected_commands_do_not_change_the_encounter():
    with client() as http:
        http.post("/encounter", json={"actors": ACTORS})
        unknown = http.post("/encounter/attack", json={**ATTACK, "target_id": "nobody"})
        assert unknown.status_code == 400
        assert "unknown actor" in unknown.json()["detail"]

        empty = http.post("/encounter/undo")
        assert empty.status_code == 409

        assert http.post("/encounter", json={"actors": {}}).status_code == 400
        assert http.post("/encounter/attack", json={**ATTACK, "distance_m": -1}).status_code == 422
        assert http.post("/encounter/attack", json={**ATTACK, "mode": "railgun"}).status_code == 422


def test_a_head_shot_must_be_aimed():
    with client() as http:
        http.post("/encounter", json={"actors": ACTORS})
        refused = http.post("/encounter/attack", json={**ATTACK, "location": "head"})
        assert refused.status_code == 400
        assert "aimed" in refused.json()["detail"]
