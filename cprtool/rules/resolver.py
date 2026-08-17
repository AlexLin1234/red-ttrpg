"""Pure Cyberpunk RED combat resolution.

This module deliberately imports only the Python standard library. It performs
no I/O and mutates neither the request nor the supplied table provider. All
state changes are described as events for a separate applier.

The constants below are intentionally marked for the Phase 1 operator audit.
They are working values, not a substitute for checking the licensed book.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from random import Random
from typing import Any, Literal, Mapping, Protocol


RULES: dict[str, int | bool] = {
    "hit_requires_meeting_dv": False,  # core rulebook p. 172: defender wins a tie
    "opposed_hit_requires_exceeding_dv": True,  # core rulebook p. 129: defender wins a tie
    "ablate_on_stopped_hit": False,  # core rulebook p. 186: ablate only after damage
    "crit_injury_bonus_damage": 5,  # core rulebook p. 187
    "critical_trigger_sixes": 2,  # core rulebook p. 187
    "headshot_multiplier": 2,  # core rulebook p. 170: after head SP
    "min_damage_through_armor": 0,  # core rulebook p. 186
    "aimed_shot_modifier": -8,  # core rulebook p. 170
    "autofire_ammo_cost": 10,  # core rulebook p. 173
    "autofire_damage_dice": 2,  # core rulebook p. 173
    "cover_blocks_overflow": True,  # core rulebook p. 182
    "poor_quality_jams_on_one": True,  # core rulebook p. 342
    "excellent_quality_attack_bonus": 1,  # core rulebook p. 342
}


Location = Literal["body", "head"]
FireMode = Literal["single", "aimed", "autofire"]
WeaponQuality = Literal["poor", "standard", "excellent"]
Event = dict[str, Any]


class RandomSource(Protocol):
    """The small RNG surface used by the resolver."""

    def randint(self, a: int, b: int) -> int: ...


@dataclass(frozen=True, slots=True)
class Weapon:
    """The already-looked-up numeric properties of a weapon."""

    name: str
    weapon_type: str
    damage_dice: int
    rof: int = 1
    magazine: int = 1
    autofire_rating: int | None = None
    quality: WeaponQuality = "standard"

    def __post_init__(self) -> None:
        if self.damage_dice <= 0:
            raise ValueError("damage_dice must be positive")
        if self.rof <= 0:
            raise ValueError("rof must be positive")
        if self.magazine <= 0:
            raise ValueError("magazine must be positive")
        if self.autofire_rating is not None and self.autofire_rating <= 0:
            raise ValueError("autofire_rating must be positive")


@dataclass(frozen=True, slots=True)
class TargetState:
    """Only the target state required for one attack resolution."""

    target_id: str
    hp: int
    max_hp: int
    body_sp: int = 0
    head_sp: int = 0
    cover_hp: int = 0

    def __post_init__(self) -> None:
        if self.max_hp <= 0:
            raise ValueError("max_hp must be positive")
        if self.hp > self.max_hp:
            raise ValueError("hp cannot exceed max_hp")
        if min(self.body_sp, self.head_sp, self.cover_hp) < 0:
            raise ValueError("SP and cover HP cannot be negative")


@dataclass(frozen=True, slots=True)
class AttackRequest:
    attacker_id: str
    target: TargetState
    weapon: Weapon
    attack_base: int
    distance_m: float
    ammo: int
    location: Location = "body"
    mode: FireMode = "single"
    defender_evasion_base: int | None = None
    modifiers: int = 0

    def __post_init__(self) -> None:
        if self.distance_m < 0:
            raise ValueError("distance_m cannot be negative")
        if self.ammo < 0:
            raise ValueError("ammo cannot be negative")
        if self.location == "head" and self.mode != "aimed":
            raise ValueError("a head attack must use aimed mode")
        if self.mode == "autofire" and self.weapon.autofire_rating is None:
            raise ValueError("weapon does not support autofire")


@dataclass(frozen=True, slots=True)
class Roll:
    rolls: tuple[int, ...]
    total: int


@dataclass(frozen=True, slots=True)
class AttackResult:
    hit: bool
    attack_roll: Roll
    defense: int
    defense_kind: Literal["range", "evasion"]
    damage_rolls: tuple[int, ...] = ()
    raw_damage: int = 0
    armor_sp: int = 0
    armor_damage: int = 0
    hp_damage: int = 0
    critical_injury: str | None = None
    events: tuple[Event, ...] = field(default_factory=tuple)
    card_lines: tuple[str, ...] = field(default_factory=tuple)


def roll_check(rng: RandomSource) -> Roll:
    """Roll a RED d10 check, including exploding 10s and subtracting fumbles."""

    first = rng.randint(1, 10)
    rolls = [first]
    total = first
    if first == 10:
        extra = rng.randint(1, 10)
        rolls.append(extra)
        total += extra
    elif first == 1:
        extra = rng.randint(1, 10)
        rolls.append(extra)
        total -= extra
    return Roll(tuple(rolls), total)


def _damage_roll(dice: int, rng: RandomSource) -> tuple[tuple[int, ...], int]:
    rolls = tuple(rng.randint(1, 6) for _ in range(dice))
    return rolls, sum(rolls)


def _meets_defense(total: int, defense: int, kind: str) -> bool:
    if kind == "evasion":
        return total > defense if RULES["opposed_hit_requires_exceeding_dv"] else total >= defense
    return total >= defense if RULES["hit_requires_meeting_dv"] else total > defense


def resolve_attack(
    request: AttackRequest,
    tables: Any,
    rng: RandomSource | None = None,
) -> AttackResult:
    """Resolve one ranged attack and return descriptive events.

    ``tables`` is intentionally duck-typed so this pure module does not import
    the I/O-capable table adapter. It must provide ``ranged_dv`` and
    ``critical_injury`` methods.
    """

    ammo_cost = int(RULES["autofire_ammo_cost"]) if request.mode == "autofire" else 1
    if request.ammo < ammo_cost:
        raise ValueError("cannot attack with an empty weapon")
    rng = rng or Random()
    events: list[Event] = [
        {
            "kind": "ammo_spent",
            "actor_id": request.attacker_id,
            "weapon": request.weapon.name,
            "amount": ammo_cost,
        }
    ]

    check = roll_check(rng)
    aimed_modifier = int(RULES["aimed_shot_modifier"]) if request.mode == "aimed" else 0
    quality_modifier = int(RULES["excellent_quality_attack_bonus"]) if request.weapon.quality == "excellent" else 0
    attack_total = request.attack_base + request.modifiers + aimed_modifier + quality_modifier + check.total

    if request.weapon.quality == "poor" and check.rolls[0] == 1 and RULES["poor_quality_jams_on_one"]:
        events.append(
            {
                "kind": "weapon_jammed",
                "actor_id": request.attacker_id,
                "weapon": request.weapon.name,
            }
        )

    if request.defender_evasion_base is None:
        defense_kind: Literal["range", "evasion"] = "range"
        if request.mode == "autofire":
            defense = int(tables.autofire_dv(request.weapon.weapon_type, request.distance_m))
        else:
            defense = int(tables.ranged_dv(request.weapon.weapon_type, request.distance_m))
        defense_card = f"DV {defense} (range)"
    else:
        defense_kind = "evasion"
        defense_roll = roll_check(rng)
        defense = request.defender_evasion_base + defense_roll.total
        defense_card = f"Defense {defense} (evasion)"

    attack_card = (
        f"Attack: base {request.attack_base} + d10 {check.total}"
        f" + modifiers {request.modifiers + aimed_modifier + quality_modifier} = {attack_total}"
    )
    if not _meets_defense(attack_total, defense, defense_kind):
        events.append(
            {
                "kind": "attack_missed",
                "actor_id": request.attacker_id,
                "target_id": request.target.target_id,
            }
        )
        return AttackResult(
            hit=False,
            attack_roll=check,
            defense=defense,
            defense_kind=defense_kind,
            events=tuple(events),
            card_lines=(attack_card, defense_card, "MISS"),
        )

    damage_dice = int(RULES["autofire_damage_dice"]) if request.mode == "autofire" else request.weapon.damage_dice
    damage_rolls, base_damage = _damage_roll(damage_dice, rng)
    multiplier = 1
    if request.mode == "autofire":
        margin = attack_total - defense
        multiplier = int(tables.autofire_multiplier(margin, request.weapon.autofire_rating))
    raw_damage = base_damage * multiplier
    damage_text = f"Damage: {' + '.join(map(str, damage_rolls))} = {base_damage}"
    if multiplier != 1:
        damage_text += f"; x {multiplier} = {raw_damage}"
    card_lines = [attack_card, defense_card, damage_text]

    # Cover is binary in RED: it takes the hit instead of the target. Damage in
    # excess of the cover's remaining HP does not pass through this attack.
    if request.target.cover_hp > 0:
        events.append(
            {
                "kind": "cover_damaged",
                "target_id": request.target.target_id,
                "amount": raw_damage,
            }
        )
        remaining_cover = max(0, request.target.cover_hp - raw_damage)
        card_lines.append(
            f"Cover: {request.target.cover_hp} HP - {raw_damage} = {remaining_cover} HP"
        )
        return AttackResult(
            hit=True,
            attack_roll=check,
            defense=defense,
            defense_kind=defense_kind,
            damage_rolls=damage_rolls,
            raw_damage=raw_damage,
            events=tuple(events),
            card_lines=tuple(card_lines),
        )

    armor_sp = request.target.head_sp if request.location == "head" else request.target.body_sp
    penetrates = raw_damage > armor_sp
    after_armor = max(int(RULES["min_damage_through_armor"]), raw_damage - armor_sp) if penetrates else 0
    location_multiplier = int(RULES["headshot_multiplier"]) if request.location == "head" else 1
    armor_damage = after_armor * location_multiplier

    if penetrates or RULES["ablate_on_stopped_hit"]:
        events.append(
            {
                "kind": "armor_ablated",
                "target_id": request.target.target_id,
                "location": request.location,
                "amount": 1,
            }
        )

    critical_injury: str | None = None
    critical_bonus = 0
    if sum(value == 6 for value in damage_rolls) >= int(RULES["critical_trigger_sixes"]):
        injury_rolls, injury_total = _damage_roll(2, rng)
        injury = tables.critical_injury(request.location, injury_total)
        critical_injury = str(injury["name"] if isinstance(injury, Mapping) else injury.name)
        critical_bonus = int(RULES["crit_injury_bonus_damage"])
        events.append(
            {
                "kind": "critical_injury",
                "target_id": request.target.target_id,
                "location": request.location,
                "injury": critical_injury,
                "rolls": injury_rolls,
            }
        )

    hp_damage = armor_damage + critical_bonus
    if hp_damage:
        events.append(
            {
                "kind": "damage_taken",
                "target_id": request.target.target_id,
                "amount": hp_damage,
            }
        )

    new_hp = request.target.hp - hp_damage
    serious_threshold = (request.target.max_hp - 1) // 2
    if request.target.hp > serious_threshold >= new_hp:
        events.append({"kind": "seriously_wounded", "target_id": request.target.target_id})
    if new_hp <= 0:
        events.append({"kind": "death_save_due", "target_id": request.target.target_id})

    card_lines.append(f"Armor: {raw_damage} - SP {armor_sp} = {after_armor}")
    if location_multiplier != 1:
        card_lines.append(f"Head: {after_armor} x {location_multiplier} = {armor_damage}")
    if critical_bonus:
        card_lines.append(f"Critical Injury ({critical_injury}): +{critical_bonus} direct HP")
    card_lines.append(f"HP damage: {armor_damage} + {critical_bonus} = {hp_damage}")

    return AttackResult(
        hit=True,
        attack_roll=check,
        defense=defense,
        defense_kind=defense_kind,
        damage_rolls=damage_rolls,
        raw_damage=raw_damage,
        armor_sp=armor_sp,
        armor_damage=armor_damage,
        hp_damage=hp_damage,
        critical_injury=critical_injury,
        events=tuple(events),
        card_lines=tuple(card_lines),
    )


__all__ = [
    "AttackRequest",
    "AttackResult",
    "Event",
    "RULES",
    "Roll",
    "TargetState",
    "Weapon",
    "resolve_attack",
    "roll_check",
]
