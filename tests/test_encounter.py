from __future__ import annotations

import pytest

from cprtool.gm.encounter import Encounter
from cprtool.rules.tables import WeaponProfile


class FixedRng:
    def __init__(self, *rolls: int) -> None:
        self.rolls = iter(rolls)

    def randint(self, low: int, high: int) -> int:
        value = next(self.rolls)
        assert low <= value <= high
        return value


class FakeTables:
    def __init__(self, dv: int = 13) -> None:
        self.dv = dv

    def ranged_dv(self, weapon_type: str, distance_m: float) -> int:
        return self.dv

    def autofire_dv(self, weapon_type: str, distance_m: float) -> int:
        return self.dv

    def autofire_multiplier(self, margin: int, rating: int | None) -> int:
        assert rating is not None
        return min(margin, rating)

    def critical_injury(self, location: str, roll: int):
        return {"name": f"Test {location} injury {roll}", "page": 187}

    def weapon(self, name: str) -> WeaponProfile:
        return WeaponProfile(
            name=name,
            range_type="pistol",
            skill="Handgun",
            damage_dice=3,
            magazine=8,
            rof=2,
            hands=1,
            concealable=True,
            autofire_rating=None,
            page=341,
        )


def encounter(*rolls: int, dv: int = 13) -> Encounter:
    return Encounter(
        FakeTables(dv),
        {
            "solo": {
                "name": "Rache",
                "max_hp": 40,
                "attack_base": 12,
                "evasion_base": 10,
                "weapons": {"Heavy Pistol": {"ammo": 8, "weapon_type": "pistol", "damage_dice": 3, "magazine": 8}},
            },
            "goon": {
                "name": "Booster",
                "max_hp": 40,
                "hp": 30,
                "armor": {"body": 7, "head": 7},
                "evasion_base": 8,
                "weapons": {},
            },
        },
        FixedRng(*rolls),
    )


def strike(session: Encounter, **overrides):
    command = {
        "attacker_id": "solo",
        "target_id": "goon",
        "weapon": "Heavy Pistol",
        "distance_m": 5,
    }
    command.update(overrides)
    return session.attack(**command)


def actor(snapshot, actor_id: str):
    return next(entry for entry in snapshot["actors"] if entry["id"] == actor_id)


def test_load_fills_defaults_and_reports_a_drawable_snapshot():
    snapshot = encounter().snapshot()
    goon = actor(snapshot, "goon")
    assert snapshot["type"] == "snapshot"
    assert goon["name"] == "Booster"
    assert goon["wound_state"] == "unhurt"
    assert goon["death_save_due"] is False
    assert goon["critical_injuries"] == []
    assert actor(snapshot, "solo")["hp"] == 40  # hp defaults to max_hp
    weapon = actor(snapshot, "solo")["weapons"][0]
    assert weapon["name"] == "Heavy Pistol"
    assert weapon["ammo"] == 8
    assert weapon["jammed"] is False
    assert weapon["weapon_type"] == "pistol"
    assert weapon["damage_dice"] == 3
    assert weapon["rof"] == 1
    assert weapon["magazine"] == 8
    assert weapon["autofire_rating"] is None
    assert weapon["quality"] == "standard"
    solo = actor(snapshot, "solo")
    assert solo["attack_base"] == 12
    assert solo["evasion_base"] == 10
    assert solo["selected_weapon"] == "Heavy Pistol"
    assert solo["skills"] == {}
    assert solo["cash"] == 0
    assert solo["lifestyle"]["key"] == "kibble"
    assert solo["lifestyle"]["monthly_cost"] == 100
    assert snapshot["card"] is None
    assert snapshot["can_undo"] is False


def test_attack_spends_ammo_applies_damage_and_renders_a_card():
    session = encounter(8, 4, 4, 4)
    snapshot = strike(session)
    assert actor(snapshot, "goon")["hp"] == 25
    assert actor(snapshot, "solo")["weapons"][0]["ammo"] == 7
    assert snapshot["card"]["title"] == "HIT"
    assert snapshot["card"]["attacker"] == "Rache"
    assert snapshot["card"]["target"] == "Booster"
    assert snapshot["card"]["hp_damage"] == 5
    assert snapshot["card"]["lines"]
    assert snapshot["events"][0]["kind"] == "ammo_spent"
    assert snapshot["result"]["hit"] is True
    assert snapshot["can_undo"] is True


def test_miss_is_titled_and_costs_only_ammo():
    session = encounter(2, dv=20)
    snapshot = strike(session)
    assert snapshot["card"]["title"] == "MISS"
    assert snapshot["card"]["hit"] is False
    assert actor(snapshot, "goon")["hp"] == 30
    assert actor(snapshot, "solo")["weapons"][0]["ammo"] == 7


def test_undo_restores_the_previous_state_and_redo_replays_it():
    session = encounter(8, 4, 4, 4)
    strike(session)
    undone = session.undo()
    assert actor(undone, "goon")["hp"] == 30
    assert actor(undone, "solo")["weapons"][0]["ammo"] == 8
    assert undone["card"]["title"] == "UNDO"
    assert any(event["kind"] == "damage_healed" for event in undone["events"])
    assert undone["can_redo"] is True

    redone = session.redo()
    assert actor(redone, "goon")["hp"] == 25
    assert actor(redone, "solo")["weapons"][0]["ammo"] == 7
    assert redone["card"]["title"] == "REDO"


def test_nothing_to_undo_raises():
    with pytest.raises(IndexError):
        encounter().undo()


def test_wound_state_and_death_save_reach_the_viewer():
    session = Encounter(
        FakeTables(),
        {
            "solo": {"max_hp": 40, "attack_base": 12, "weapons": {"Heavy Pistol": {"ammo": 8, "weapon_type": "pistol", "damage_dice": 3}}},
            "goon": {"max_hp": 20, "hp": 10, "weapons": {}},
        },
        FixedRng(8, 4, 4, 4),
    )
    snapshot = strike(session)
    goon = actor(snapshot, "goon")
    assert goon["hp"] == -2
    assert goon["wound_state"] == "seriously_wounded"
    assert goon["death_save_due"] is True


def test_critical_injury_is_named_on_the_card():
    session = encounter(8, 6, 6, 2, 3, 4)
    snapshot = strike(session)
    assert snapshot["card"]["title"] == "CRITICAL INJURY"
    assert snapshot["card"]["critical_injury"] == "Test body injury 7"
    assert actor(snapshot, "goon")["critical_injuries"] == ["Test body injury 7"]


def test_cover_absorbs_the_hit_instead_of_the_target():
    session = Encounter(
        FakeTables(),
        {
            "solo": {"max_hp": 40, "attack_base": 12, "weapons": {"Heavy Pistol": {"ammo": 8, "weapon_type": "pistol", "damage_dice": 3}}},
            "goon": {"max_hp": 40, "hp": 30, "cover_hp": 10, "weapons": {}},
        },
        FixedRng(8, 4, 4, 4),
    )
    snapshot = strike(session)
    goon = actor(snapshot, "goon")
    assert goon["cover_hp"] == 0 and goon["hp"] == 30
    assert snapshot["card"]["title"] == "STOPPED"


def test_a_jammed_weapon_must_be_cleared_before_firing():
    session = encounter(1, 4)
    session.session.state["actors"]["solo"]["weapons"]["Heavy Pistol"]["jammed"] = True
    with pytest.raises(ValueError, match="jammed"):
        strike(session)

    snapshot = session.clear_jam(actor_id="solo", weapon="Heavy Pistol")
    assert actor(snapshot, "solo")["weapons"][0]["jammed"] is False
    assert snapshot["card"]["title"] == "JAM CLEARED"
    assert actor(session.undo(), "solo")["weapons"][0]["jammed"] is True


def test_reload_refills_the_magazine_and_is_reversible():
    session = encounter(2, dv=20)
    strike(session)
    snapshot = session.reload(actor_id="solo", weapon="Heavy Pistol")
    assert actor(snapshot, "solo")["weapons"][0]["ammo"] == 8
    assert actor(session.undo(), "solo")["weapons"][0]["ammo"] == 7

    with pytest.raises(ValueError, match="does not need"):
        session.reload(actor_id="solo", weapon="Heavy Pistol", amount=0)


def test_reload_cannot_overfill_the_magazine():
    session = encounter(2, dv=20)
    strike(session)
    with pytest.raises(ValueError, match="at most 1"):
        session.reload(actor_id="solo", weapon="Heavy Pistol", amount=2)


def test_attack_cover_snapshot_is_event_sourced_and_reversible():
    session = encounter(8, 4, 4, 4)
    covered = strike(session, cover_hp=20, cover_id="BlueBarrier")
    assert actor(covered, "goon")["cover_hp"] == 8
    assert covered["covers"] == {"BlueBarrier": 8}
    assert actor(covered, "goon")["hp"] == 30
    assert [event["kind"] for event in covered["events"]] == [
        "cover_set",
        "ammo_spent",
        "cover_damaged",
    ]

    undone = session.undo()
    assert actor(undone, "goon")["cover_hp"] == 0
    assert undone["covers"] == {}
    assert any(event["kind"] == "cover_restored" for event in undone["events"])

    redone = session.redo()
    assert redone["covers"] == {"BlueBarrier": 8}
    cover_damage = next(event for event in redone["events"] if event["kind"] == "cover_damaged")
    assert cover_damage["cover_id"] == "BlueBarrier"


def test_cover_identity_requires_a_cover_hp_measurement():
    session = encounter()
    with pytest.raises(ValueError, match="cover_id requires cover_hp"):
        strike(session, cover_id="BlueBarrier")


def test_unknown_minimal_weapon_remains_drawable_until_used():
    class RejectingTables(FakeTables):
        def weapon(self, name: str) -> WeaponProfile:
            raise KeyError(name)

    session = Encounter(
        RejectingTables(),
        {"solo": {"max_hp": 40, "weapons": {"Homebrew": {"ammo": 3}}}},
    )
    weapon = actor(session.snapshot(), "solo")["weapons"][0]
    assert weapon["name"] == "Homebrew"
    assert weapon["ammo"] == 3
    assert weapon["weapon_type"] == "unknown"


def test_weapon_stats_fall_back_to_the_validated_tables():
    session = Encounter(
        FakeTables(),
        {
            "solo": {"max_hp": 40, "attack_base": 12, "weapons": {"Heavy Pistol": {"ammo": 8}}},
            "goon": {"max_hp": 40, "hp": 30, "armor": {"body": 7, "head": 7}, "weapons": {}},
        },
        FixedRng(8, 4, 4, 4),
    )
    snapshot = strike(session)
    assert actor(snapshot, "goon")["hp"] == 25  # three d6 from the table profile


def test_unknown_actors_and_weapons_are_rejected():
    session = encounter()
    with pytest.raises(KeyError, match="unknown actor"):
        strike(session, target_id="nobody")
    with pytest.raises(KeyError, match="not carrying"):
        strike(session, weapon="Sniper Rifle")


def test_loading_an_encounter_requires_actors():
    with pytest.raises(ValueError, match="at least one actor"):
        encounter().load({})


def test_month_end_auto_pays_lifestyles_marks_debt_and_is_reversible():
    session = Encounter(
        FakeTables(),
        {
            "rich": {
                "name": "Rogue",
                "max_hp": 40,
                "cash": 1_000,
                "lifestyle": "good_prepak",
            },
            "poor": {
                "name": "Redeye",
                "max_hp": 30,
                "cash": 99,
                "lifestyle": "kibble",
            },
        },
        current_month="2045-01",
    )

    closed = session.close_month()
    rich = actor(closed, "rich")
    poor = actor(closed, "poor")
    assert rich["cash"] == 400
    assert rich["lifestyle_status"] == "current"
    assert rich["lifestyle_paid_through"] == "2045-02"
    assert poor["cash"] == 99
    assert poor["lifestyle_status"] == "unpaid"
    assert poor["lifestyle_balance_due"] == 100
    assert poor["lifestyle_grace_days"] == 7
    assert closed["calendar"]["current_month"] == "2045-02"
    assert closed["result"]["total_deducted"] == 600
    assert [event["kind"] for event in closed["events"]] == [
        "lifestyle_charged",
        "lifestyle_unpaid",
        "month_closed",
    ]

    undone = session.undo()
    assert actor(undone, "rich")["cash"] == 1_000
    assert actor(undone, "poor")["lifestyle_status"] == "current"
    assert undone["calendar"]["current_month"] == "2045-01"

    redone = session.redo()
    assert actor(redone, "rich")["cash"] == 400
    assert redone["calendar"]["current_month"] == "2045-02"


def test_months_must_close_in_order():
    session = encounter()
    with pytest.raises(ValueError, match="next month to close is 2045-01"):
        session.close_month(month="2045-02")


def test_hp_cannot_start_above_max():
    with pytest.raises(ValueError, match="cannot exceed"):
        Encounter(FakeTables(), {"solo": {"max_hp": 10, "hp": 11}})
