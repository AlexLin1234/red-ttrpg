from pathlib import Path

import pytest

from cprtool.rules.tables import JSONTables
from cprtool.rules.resolver import AttackRequest, TargetState, Weapon, resolve_attack


TABLES_PATH = Path(__file__).parents[1] / "cprtool" / "rules" / "tables.json"


@pytest.fixture(scope="module")
def tables():
    if not TABLES_PATH.exists():
        pytest.skip("operator-local tables.json has not been promoted")
    return JSONTables(TABLES_PATH)


def test_known_single_shot_ranges(tables):
    assert tables.ranged_dv("pistol", 5) == 13
    assert tables.ranged_dv("assault_rifle", 30) == 13
    assert tables.ranged_dv("sniper_rifle", 75) == 15


def test_invalid_range_is_rejected(tables):
    with pytest.raises(ValueError):
        tables.ranged_dv("pistol", 250)


def test_known_autofire_ranges_and_cap(tables):
    assert tables.autofire_dv("smg", 10) == 17
    assert tables.autofire_dv("assault_rifle", 20) == 17
    assert tables.autofire_multiplier(7, 4) == 4


def test_every_weapon_has_positive_damage_and_rof(tables):
    for name in tables._data["weapons"]:
        weapon = tables.weapon(name)
        assert weapon.damage_dice > 0 and weapon.rof > 0


def test_weapon_stats_match_hand_checked_rows(tables):
    pistol = tables.weapon("Heavy Pistol")
    rifle = tables.weapon("Assault Rifle")
    assert (pistol.damage_dice, pistol.magazine, pistol.rof) == (3, 8, 2)
    assert (rifle.damage_dice, rifle.magazine, rifle.autofire_rating) == (5, 25, 4)


def test_armor_rows(tables):
    assert tables.armor("Light Armorjack").sp == 11
    assert tables.armor("Metalgear").penalty["REF"] == -4


def test_critical_injury_tables_cover_every_roll(tables):
    for location in ("body", "head"):
        entries = [tables.critical_injury(location, roll) for roll in range(2, 13)]
        assert len(entries) == 11 and all(entry.name and entry.page in {187, 188} for entry in entries)


def test_cover_and_aimed_shot_references(tables):
    assert tables.cover("Overturned Table")["hp"] == 5
    assert tables.aimed_shot("head")["modifier"] == -8


def test_resolver_runs_against_operator_json_tables(tables):
    class FixedRng:
        def __init__(self):
            self.values = iter((5, 4, 4, 4))

        def randint(self, low, high):
            return next(self.values)

    result = resolve_attack(
        AttackRequest(
            attacker_id="solo",
            target=TargetState("goon", hp=30, max_hp=40, body_sp=7),
            weapon=Weapon("Heavy Pistol", "pistol", 3, magazine=8),
            attack_base=9,
            distance_m=5,
            ammo=8,
        ),
        tables,
        FixedRng(),
    )
    assert result.hit is True and result.defense == 13 and result.hp_damage == 5
