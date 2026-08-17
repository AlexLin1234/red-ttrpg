from __future__ import annotations

import random
from copy import deepcopy

from cprtool.rules.events import Session, apply
from cprtool.rules.resolver import AttackRequest, TargetState, Weapon, resolve_attack


class TestTables:
    def ranged_dv(self, weapon_type: str, distance_m: float) -> int:
        return 13

    def autofire_dv(self, weapon_type: str, distance_m: float) -> int:
        return 17

    def autofire_multiplier(self, margin: int, rating: int | None) -> int:
        return min(margin, rating or 1)

    def critical_injury(self, location: str, roll: int):
        return {"name": f"Injury {location} {roll}", "page": 187}


def world(target: TargetState, weapon: Weapon, ammo: int) -> dict:
    return {
        "actors": {
            "solo": {"weapons": {weapon.name: {"ammo": ammo, "jammed": False}}},
            "goon": {
                "hp": target.hp,
                "max_hp": target.max_hp,
                "armor": {"body": target.body_sp, "head": target.head_sp},
                "cover_hp": target.cover_hp,
                "critical_injuries": [],
                "wound_state": "lightly_wounded",
                "death_save_due": False,
            },
        }
    }


def test_apply_then_inverse_restores_exact_state():
    target = TargetState("goon", 30, 40, body_sp=7)
    weapon = Weapon("Heavy Pistol", "pistol", 3, magazine=8)
    before = world(target, weapon, 8)
    result = resolve_attack(AttackRequest("solo", target, weapon, 14, 5, 8), TestTables(), random.Random(7))
    after, inverse = apply(before, result.events)
    restored, _ = apply(after, inverse)
    assert restored == before
    assert before == world(target, weapon, 8)


def test_session_undo_redo_and_new_action_clears_redo():
    target = TargetState("goon", 30, 40, body_sp=0)
    weapon = Weapon("Heavy Pistol", "pistol", 3, magazine=8)
    initial = world(target, weapon, 8)
    result = resolve_attack(AttackRequest("solo", target, weapon, 20, 5, 8), TestTables(), random.Random(3))
    session = Session(deepcopy(initial))
    resolved = session.record({"kind": "attack"}, result.events)
    assert session.undo() == initial
    assert session.redo() == resolved
    session.undo()
    session.record({"kind": "miss"}, ({"kind": "attack_missed", "target_id": "goon"},))
    assert not session.redo_log


def test_cover_assignment_and_damage_reverse_as_one_action():
    target = TargetState("goon", 30, 40)
    weapon = Weapon("Heavy Pistol", "pistol", 3, magazine=8)
    before = world(target, weapon, 8)
    events = (
        {"kind": "cover_set", "target_id": "goon", "hp": 20, "cover_id": "crate"},
        {"kind": "cover_damaged", "target_id": "goon", "amount": 12, "cover_id": "crate"},
    )
    after, inverse = apply(before, events)
    assert after["actors"]["goon"]["cover_hp"] == 8
    restored, _ = apply(after, inverse)
    assert restored == before
    assert inverse[0]["cover_id"] == "crate"
    assert inverse[1]["affected_cover_id"] == "crate"


def test_one_thousand_random_attacks_round_trip():
    generator = random.Random(20260815)
    tables = TestTables()
    for _ in range(1_000):
        max_hp = generator.randint(20, 60)
        target = TargetState(
            "goon",
            hp=generator.randint(1, max_hp),
            max_hp=max_hp,
            body_sp=generator.randint(0, 15),
            head_sp=generator.randint(0, 15),
            cover_hp=generator.choice([0, 0, 0, 5, 10, 20]),
        )
        weapon = Weapon("Test Gun", "pistol", generator.randint(2, 6), magazine=20)
        before = world(target, weapon, 20)
        result = resolve_attack(
            AttackRequest("solo", target, weapon, generator.randint(5, 20), generator.randint(0, 6), 20),
            tables,
            random.Random(generator.getrandbits(64)),
        )
        after, inverse = apply(before, result.events)
        restored, _ = apply(after, inverse)
        assert restored == before


def test_undo_depth_is_not_capped():
    target = TargetState("goon", 30, 40)
    weapon = Weapon("Heavy Pistol", "pistol", 3, magazine=200)
    initial = world(target, weapon, 200)
    session = Session(deepcopy(initial))
    for index in range(100):
        session.record({"index": index}, ({"kind": "ammo_spent", "actor_id": "solo", "weapon": weapon.name, "amount": 1},))
    for _ in range(100):
        session.undo()
    assert session.state == initial
