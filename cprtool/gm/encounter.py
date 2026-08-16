"""Live encounter state for the viewer.

This module owns no rules arithmetic of its own. It reads actor state, hands
the numbers to the pure resolver, records the resulting events through the
reversible session log, and renders a snapshot the Godot viewer can draw.
"""

from __future__ import annotations

from copy import deepcopy
from typing import Any, Mapping

from cprtool.rules.events import Session
from cprtool.rules.resolver import (
    AttackRequest,
    AttackResult,
    RandomSource,
    TargetState,
    Weapon,
    resolve_attack,
)


DEFAULT_ARMOR: dict[str, int] = {"body": 0, "head": 0}


def _normalise_weapon(entry: Mapping[str, Any]) -> dict[str, Any]:
    weapon = dict(entry)
    weapon["ammo"] = int(weapon.get("ammo", 0))
    weapon["jammed"] = bool(weapon.get("jammed", False))
    if weapon["ammo"] < 0:
        raise ValueError("ammo cannot be negative")
    return weapon


def _normalise_actor(actor_id: str, entry: Mapping[str, Any]) -> dict[str, Any]:
    actor = dict(entry)
    actor["name"] = str(actor.get("name", actor_id))
    actor["max_hp"] = int(actor["max_hp"])
    actor["hp"] = int(actor.get("hp", actor["max_hp"]))
    if actor["max_hp"] <= 0:
        raise ValueError(f"{actor_id}: max_hp must be positive")
    if actor["hp"] > actor["max_hp"]:
        raise ValueError(f"{actor_id}: hp cannot exceed max_hp")
    armor = {**DEFAULT_ARMOR, **dict(actor.get("armor", {}))}
    actor["armor"] = {"body": int(armor["body"]), "head": int(armor["head"])}
    if min(actor["armor"].values()) < 0:
        raise ValueError(f"{actor_id}: SP cannot be negative")
    actor["cover_hp"] = int(actor.get("cover_hp", 0))
    if actor["cover_hp"] < 0:
        raise ValueError(f"{actor_id}: cover HP cannot be negative")
    actor["wound_state"] = str(actor.get("wound_state", "unhurt"))
    actor["death_save_due"] = bool(actor.get("death_save_due", False))
    actor["critical_injuries"] = [str(injury) for injury in actor.get("critical_injuries", [])]
    actor["weapons"] = {
        str(name): _normalise_weapon(weapon) for name, weapon in dict(actor.get("weapons", {})).items()
    }
    return actor


class Encounter:
    """A single reversible encounter shared by the GM console and the viewer.

    ``tables`` is duck-typed for the same reason the resolver duck-types it:
    the operator's validated table file is the only source of printed numbers,
    and the encounter must not grow a second copy of them.
    """

    def __init__(
        self,
        tables: Any,
        actors: Mapping[str, Mapping[str, Any]] | None = None,
        rng: RandomSource | None = None,
    ) -> None:
        self.tables = tables
        self.rng = rng
        self.session = Session({"actors": {}})
        self.revision = 0
        self.card: dict[str, Any] | None = None
        if actors is not None:
            self.load(actors)

    # -- state ---------------------------------------------------------------

    def load(self, actors: Mapping[str, Mapping[str, Any]]) -> dict[str, Any]:
        """Replace the encounter. Loading clears undo history by design."""

        if not actors:
            raise ValueError("an encounter needs at least one actor")
        state = {"actors": {str(key): _normalise_actor(str(key), value) for key, value in actors.items()}}
        self.session = Session(state)
        self.revision += 1
        self.card = None
        return self.snapshot()

    def _actor(self, actor_id: str) -> dict[str, Any]:
        try:
            return self.session.state["actors"][actor_id]
        except KeyError as exc:
            raise KeyError(f"unknown actor: {actor_id}") from exc

    def _weapon_state(self, actor_id: str, weapon_name: str) -> dict[str, Any]:
        try:
            return self._actor(actor_id)["weapons"][weapon_name]
        except KeyError as exc:
            raise KeyError(f"{actor_id} is not carrying {weapon_name}") from exc

    def _weapon(self, actor_id: str, weapon_name: str) -> Weapon:
        entry = self._weapon_state(actor_id, weapon_name)
        quality = str(entry.get("quality", "standard"))
        if "damage_dice" in entry:
            return Weapon(
                name=weapon_name,
                weapon_type=str(entry["weapon_type"]),
                damage_dice=int(entry["damage_dice"]),
                rof=int(entry.get("rof", 1)),
                magazine=int(entry.get("magazine", 1)),
                autofire_rating=None if entry.get("autofire_rating") is None else int(entry["autofire_rating"]),
                quality=quality,  # type: ignore[arg-type]
            )
        profile = self.tables.weapon(weapon_name)
        return Weapon(
            name=weapon_name,
            weapon_type=profile.range_type,
            damage_dice=profile.damage_dice,
            rof=profile.rof,
            magazine=profile.magazine or 1,
            autofire_rating=profile.autofire_rating,
            quality=quality,  # type: ignore[arg-type]
        )

    def _target_state(self, target_id: str) -> TargetState:
        actor = self._actor(target_id)
        return TargetState(
            target_id=target_id,
            hp=int(actor["hp"]),
            max_hp=int(actor["max_hp"]),
            body_sp=int(actor["armor"]["body"]),
            head_sp=int(actor["armor"]["head"]),
            cover_hp=int(actor["cover_hp"]),
        )

    # -- actions -------------------------------------------------------------

    def attack(
        self,
        *,
        attacker_id: str,
        target_id: str,
        weapon: str,
        distance_m: float,
        location: str = "body",
        mode: str = "single",
        modifiers: int = 0,
        contested: bool = False,
    ) -> dict[str, Any]:
        attacker = self._actor(attacker_id)
        weapon_state = self._weapon_state(attacker_id, weapon)
        if weapon_state["jammed"]:
            raise ValueError(f"{weapon} is jammed and must be cleared first")
        if "attack_base" not in attacker:
            raise KeyError(f"{attacker_id} has no attack_base")
        defender_evasion_base = None
        if contested:
            target = self._actor(target_id)
            if "evasion_base" not in target:
                raise KeyError(f"{target_id} has no evasion_base")
            defender_evasion_base = int(target["evasion_base"])

        request = AttackRequest(
            attacker_id=attacker_id,
            target=self._target_state(target_id),
            weapon=self._weapon(attacker_id, weapon),
            attack_base=int(attacker["attack_base"]),
            distance_m=float(distance_m),
            ammo=int(weapon_state["ammo"]),
            location=location,  # type: ignore[arg-type]
            mode=mode,  # type: ignore[arg-type]
            defender_evasion_base=defender_evasion_base,
            modifiers=int(modifiers),
        )
        result = resolve_attack(request, self.tables, self.rng)
        action = {
            "kind": "attack",
            "attacker_id": attacker_id,
            "target_id": target_id,
            "weapon": weapon,
            "distance_m": float(distance_m),
            "location": location,
            "mode": mode,
            "modifiers": int(modifiers),
            "contested": contested,
        }
        self.session.record(action, result.events)
        self.revision += 1
        self.card = self._attack_card(action, result)
        return self.snapshot()

    def reload(self, *, actor_id: str, weapon: str, amount: int | None = None) -> dict[str, Any]:
        state = self._weapon_state(actor_id, weapon)
        magazine = int(state.get("magazine", 0)) or self._weapon(actor_id, weapon).magazine
        refill = magazine - int(state["ammo"]) if amount is None else int(amount)
        if refill <= 0:
            raise ValueError(f"{weapon} does not need a reload")
        self.session.record(
            {"kind": "reload", "actor_id": actor_id, "weapon": weapon, "amount": refill},
            ({"kind": "ammo_restored", "actor_id": actor_id, "weapon": weapon, "amount": refill},),
        )
        self.revision += 1
        self.card = {
            "kind": "reload",
            "title": "RELOAD",
            "actor": self._actor(actor_id)["name"],
            "lines": [f"{weapon}: +{refill} rounds", f"Ammo: {self._weapon_state(actor_id, weapon)['ammo']}"],
        }
        return self.snapshot()

    def clear_jam(self, *, actor_id: str, weapon: str) -> dict[str, Any]:
        state = self._weapon_state(actor_id, weapon)
        if not state["jammed"]:
            raise ValueError(f"{weapon} is not jammed")
        self.session.record(
            {"kind": "clear_jam", "actor_id": actor_id, "weapon": weapon},
            ({"kind": "weapon_unjammed", "actor_id": actor_id, "weapon": weapon},),
        )
        self.revision += 1
        self.card = {
            "kind": "clear_jam",
            "title": "JAM CLEARED",
            "actor": self._actor(actor_id)["name"],
            "lines": [f"{weapon} is ready to fire"],
        }
        return self.snapshot()

    def undo(self) -> dict[str, Any]:
        self.session.undo()
        self.revision += 1
        self.card = None
        return self.snapshot()

    def redo(self) -> dict[str, Any]:
        self.session.redo()
        self.revision += 1
        self.card = None
        return self.snapshot()

    # -- presentation --------------------------------------------------------

    def _attack_card(self, action: Mapping[str, Any], result: AttackResult) -> dict[str, Any]:
        attacker = self._actor(str(action["attacker_id"]))
        target = self._actor(str(action["target_id"]))
        if not result.hit:
            title = "MISS"
        elif result.critical_injury:
            title = "CRITICAL INJURY"
        elif result.hp_damage:
            title = "HIT"
        else:
            title = "STOPPED"
        return {
            "kind": "attack",
            "title": title,
            "attacker": attacker["name"],
            "target": target["name"],
            "weapon": str(action["weapon"]),
            "mode": str(action["mode"]),
            "location": str(action["location"]),
            "hit": result.hit,
            "hp_damage": result.hp_damage,
            "critical_injury": result.critical_injury,
            "lines": list(result.card_lines),
        }

    def _actor_view(self, actor_id: str, actor: Mapping[str, Any]) -> dict[str, Any]:
        return {
            "id": actor_id,
            "name": actor["name"],
            "hp": int(actor["hp"]),
            "max_hp": int(actor["max_hp"]),
            "armor": dict(actor["armor"]),
            "cover_hp": int(actor["cover_hp"]),
            "wound_state": actor["wound_state"],
            "death_save_due": bool(actor["death_save_due"]),
            "critical_injuries": list(actor["critical_injuries"]),
            "weapons": [
                {
                    "name": name,
                    "ammo": int(weapon["ammo"]),
                    "jammed": bool(weapon["jammed"]),
                }
                for name, weapon in actor["weapons"].items()
            ],
        }

    def snapshot(self) -> dict[str, Any]:
        return {
            "type": "snapshot",
            "revision": self.revision,
            "can_undo": bool(self.session.log),
            "can_redo": bool(self.session.redo_log),
            "actors": [
                self._actor_view(actor_id, actor)
                for actor_id, actor in self.session.state["actors"].items()
            ],
            "card": deepcopy(self.card),
        }


__all__ = ["Encounter"]
