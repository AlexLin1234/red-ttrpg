from __future__ import annotations

from dataclasses import FrozenInstanceError

import pytest

from cprtool.rules.resolver import AttackRequest, TargetState, Weapon, resolve_attack, roll_check


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
        assert weapon_type == "pistol"
        assert distance_m >= 0
        return self.dv

    def critical_injury(self, location: str, roll: int):
        return {"name": f"Test {location} injury {roll}", "page": 187}

    def autofire_dv(self, weapon_type: str, distance_m: float) -> int:
        return self.dv

    def autofire_multiplier(self, margin: int, rating: int | None) -> int:
        assert rating is not None
        return min(margin, rating)


def request(**overrides):
    values = {
        "attacker_id": "solo",
        "target": TargetState("goon", hp=30, max_hp=40, body_sp=7, head_sp=7),
        "weapon": Weapon("Heavy Pistol", "pistol", 3, magazine=8),
        "attack_base": 12,
        "distance_m": 5,
        "ammo": 8,
    }
    values.update(overrides)
    return AttackRequest(**values)


def kinds(result):
    return [event["kind"] for event in result.events]


def test_normal_check_roll():
    assert roll_check(FixedRng(7)).total == 7


def test_ten_explodes_upward_once():
    roll = roll_check(FixedRng(10, 6))
    assert roll.rolls == (10, 6) and roll.total == 16


def test_one_fumbles_downward_once():
    roll = roll_check(FixedRng(1, 6))
    assert roll.rolls == (1, 6) and roll.total == -5


def test_static_dv_tie_misses():
    result = resolve_attack(request(attack_base=8), FakeTables(13), FixedRng(5, 2, 3, 4))
    assert result.hit is False


def test_static_dv_must_be_beaten():
    result = resolve_attack(request(attack_base=9), FakeTables(13), FixedRng(5, 2, 3, 4))
    assert result.hit is True


def test_opposed_tie_misses():
    result = resolve_attack(
        request(attack_base=8, defender_evasion_base=8),
        FakeTables(),
        FixedRng(5, 5),
    )
    assert result.hit is False and result.defense_kind == "evasion"


def test_miss_spends_ammo_and_emits_no_damage():
    result = resolve_attack(request(attack_base=0), FakeTables(20), FixedRng(2))
    assert kinds(result) == ["ammo_spent", "attack_missed"]
    assert result.hp_damage == 0


def test_armor_stops_hit_without_ablation():
    result = resolve_attack(request(), FakeTables(), FixedRng(8, 2, 2, 3))
    assert result.raw_damage == 7 and result.hp_damage == 0
    assert "armor_ablated" not in kinds(result)


def test_penetrating_hit_ablates_and_damages():
    result = resolve_attack(request(), FakeTables(), FixedRng(8, 4, 4, 4))
    assert result.hp_damage == 5
    assert kinds(result)[-2:] == ["armor_ablated", "damage_taken"]


def test_head_multiplier_is_applied_after_armor():
    result = resolve_attack(
        request(location="head", mode="aimed", attack_base=20),
        FakeTables(),
        FixedRng(8, 4, 4, 4),
    )
    assert result.raw_damage == 12 and result.armor_damage == 10


def test_critical_injury_adds_direct_damage():
    result = resolve_attack(request(), FakeTables(), FixedRng(8, 6, 6, 2, 3, 4))
    assert result.critical_injury == "Test body injury 7"
    assert result.armor_damage == 7 and result.hp_damage == 12
    assert "critical_injury" in kinds(result)


def test_cover_takes_full_hit_and_stops_resolution():
    covered = TargetState("goon", hp=30, max_hp=40, body_sp=7, cover_hp=4)
    result = resolve_attack(request(target=covered), FakeTables(), FixedRng(8, 6, 6, 6))
    assert kinds(result) == ["ammo_spent", "cover_damaged"]
    assert result.hp_damage == 0 and result.critical_injury is None
    assert result.card_lines[-1] == "Cover: 4 HP - 18 = 0 HP"


def test_crossing_half_hp_emits_seriously_wounded():
    target = TargetState("goon", hp=21, max_hp=40, body_sp=0)
    result = resolve_attack(request(target=target), FakeTables(), FixedRng(8, 4, 4, 4))
    assert "seriously_wounded" in kinds(result)


def test_zero_hp_emits_death_save_due():
    target = TargetState("goon", hp=5, max_hp=40, body_sp=0)
    result = resolve_attack(request(target=target), FakeTables(), FixedRng(8, 4, 4, 4))
    assert "death_save_due" in kinds(result)


def test_empty_weapon_cannot_attack():
    with pytest.raises(ValueError, match="empty"):
        resolve_attack(request(ammo=0), FakeTables(), FixedRng())


def test_inputs_are_immutable():
    attack = request()
    with pytest.raises(FrozenInstanceError):
        attack.ammo = 7


def test_autofire_uses_margin_capped_multiplier_and_ten_rounds():
    weapon = Weapon("Assault Rifle", "assault_rifle", 5, magazine=25, autofire_rating=4)
    result = resolve_attack(
        request(weapon=weapon, mode="autofire", attack_base=17, ammo=25),
        FakeTables(17),
        FixedRng(5, 3, 4),
    )
    assert result.raw_damage == 28
    assert result.events[0]["amount"] == 10


def test_poor_weapon_jams_on_attack_check_one():
    weapon = Weapon("Junker", "pistol", 2, quality="poor")
    result = resolve_attack(request(weapon=weapon), FakeTables(30), FixedRng(1, 4))
    assert "weapon_jammed" in kinds(result)


def test_exactly_half_hp_is_not_seriously_wounded():
    target = TargetState("goon", hp=21, max_hp=40, body_sp=0)
    weapon = Weapon("Needler", "pistol", 1)
    result = resolve_attack(request(target=target, weapon=weapon), FakeTables(), FixedRng(8, 1))
    assert result.hp_damage == 1
    assert "seriously_wounded" not in kinds(result)
