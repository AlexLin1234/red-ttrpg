"""Live encounter state for the viewer.

This module owns no rules arithmetic of its own. It reads actor state, hands
the numbers to the pure resolver, records the resulting events through the
reversible session log, and renders a snapshot the Godot viewer can draw.
"""

from __future__ import annotations

from copy import deepcopy
from dataclasses import asdict
from typing import Any, Mapping

from cprtool.rules.events import Session
from cprtool.rules.lifestyle import (
    LIFESTYLES,
    lifestyle_view,
    next_month,
    normalize_lifestyle,
    validate_month,
)
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
    actor["cash"] = int(actor.get("cash", 0))
    if actor["cash"] < 0:
        raise ValueError(f"{actor_id}: cash cannot be negative")
    actor["lifestyle"] = normalize_lifestyle(str(actor.get("lifestyle", "kibble")))
    actor["lifestyle_status"] = str(actor.get("lifestyle_status", "current"))
    if actor["lifestyle_status"] not in {"current", "unpaid"}:
        raise ValueError(f"{actor_id}: Lifestyle status must be current or unpaid")
    paid_through = actor.get("lifestyle_paid_through")
    actor["lifestyle_paid_through"] = (
        validate_month(str(paid_through)) if paid_through is not None else None
    )
    actor["lifestyle_balance_due"] = int(actor.get("lifestyle_balance_due", 0))
    if actor["lifestyle_balance_due"] < 0:
        raise ValueError(f"{actor_id}: Lifestyle balance cannot be negative")
    grace_days = actor.get("lifestyle_grace_days")
    actor["lifestyle_grace_days"] = int(grace_days) if grace_days is not None else None
    actor["last_lifestyle_charge"] = int(actor.get("last_lifestyle_charge", 0))
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
        current_month: str = "2045-01",
    ) -> None:
        self.tables = tables
        self.rng = rng
        self.default_month = validate_month(current_month)
        self.session = Session(
            {
                "actors": {},
                "covers": {},
                "calendar": {"current_month": self.default_month, "closed_months": []},
            }
        )
        self.revision = 0
        self.card: dict[str, Any] | None = None
        self.events: list[dict[str, Any]] = []
        self.result: dict[str, Any] | None = None
        if actors is not None:
            self.load(actors, current_month=self.default_month)

    # -- state ---------------------------------------------------------------

    def load(
        self,
        actors: Mapping[str, Mapping[str, Any]],
        *,
        current_month: str | None = None,
    ) -> dict[str, Any]:
        """Replace the encounter. Loading clears undo history by design."""

        if not actors:
            raise ValueError("an encounter needs at least one actor")
        state = {
            "actors": {str(key): _normalise_actor(str(key), value) for key, value in actors.items()},
            "covers": {},
            "calendar": {
                "current_month": validate_month(current_month or self.default_month),
                "closed_months": [],
            },
        }
        self.session = Session(state)
        self.revision += 1
        self.card = None
        self.events = []
        self.result = None
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
        cover_hp: int | None = None,
        cover_id: str | None = None,
    ) -> dict[str, Any]:
        if cover_id is not None and cover_hp is None:
            raise ValueError("cover_id requires cover_hp")
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

        target_state = self._target_state(target_id)
        cover_events: tuple[dict[str, Any], ...] = ()
        if cover_hp is not None:
            if cover_hp < 0:
                raise ValueError("cover HP cannot be negative")
            known_cover_hp = self.session.state.get("covers", {}).get(str(cover_id))
            if cover_id is not None and known_cover_hp is not None:
                cover_hp = int(known_cover_hp)
            target_state = TargetState(
                target_id=target_state.target_id,
                hp=target_state.hp,
                max_hp=target_state.max_hp,
                body_sp=target_state.body_sp,
                head_sp=target_state.head_sp,
                cover_hp=cover_hp,
            )
            target_actor = self._actor(target_id)
            if (
                cover_hp != target_actor["cover_hp"]
                or cover_id != target_actor.get("cover_id")
                or (cover_id is not None and str(cover_id) not in self.session.state.get("covers", {}))
            ):
                cover_events = (
                    {
                        "kind": "cover_set",
                        "target_id": target_id,
                        "hp": cover_hp,
                        "cover_id": cover_id,
                    },
                )

        request = AttackRequest(
            attacker_id=attacker_id,
            target=target_state,
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
            "cover_hp": cover_hp,
            "cover_id": cover_id,
        }
        result_events = tuple(
            {**event, "cover_id": cover_id}
            if cover_id is not None and event.get("kind") == "cover_damaged"
            else event
            for event in result.events
        )
        applied_events = cover_events + result_events
        self.session.record(action, applied_events)
        self.revision += 1
        self.card = self._attack_card(action, result)
        self.events = [deepcopy(event) for event in applied_events]
        self.result = asdict(result)
        return self.snapshot()

    def reload(self, *, actor_id: str, weapon: str, amount: int | None = None) -> dict[str, Any]:
        state = self._weapon_state(actor_id, weapon)
        magazine = int(state.get("magazine", 0)) or self._weapon(actor_id, weapon).magazine
        refill = magazine - int(state["ammo"]) if amount is None else int(amount)
        if refill <= 0:
            raise ValueError(f"{weapon} does not need a reload")
        missing = magazine - int(state["ammo"])
        if refill > missing:
            raise ValueError(f"{weapon} can accept at most {missing} rounds")
        events = ({"kind": "ammo_restored", "actor_id": actor_id, "weapon": weapon, "amount": refill},)
        self.session.record(
            {"kind": "reload", "actor_id": actor_id, "weapon": weapon, "amount": refill},
            events,
        )
        self.revision += 1
        self.card = {
            "kind": "reload",
            "title": "RELOAD",
            "actor": self._actor(actor_id)["name"],
            "lines": [f"{weapon}: +{refill} rounds", f"Ammo: {self._weapon_state(actor_id, weapon)['ammo']}"],
            "tone": "neutral",
            "duration_seconds": 5.0,
        }
        self.events = [deepcopy(event) for event in events]
        self.result = {"ammo_restored": refill}
        return self.snapshot()

    def clear_jam(self, *, actor_id: str, weapon: str) -> dict[str, Any]:
        state = self._weapon_state(actor_id, weapon)
        if not state["jammed"]:
            raise ValueError(f"{weapon} is not jammed")
        events = ({"kind": "weapon_unjammed", "actor_id": actor_id, "weapon": weapon},)
        self.session.record(
            {"kind": "clear_jam", "actor_id": actor_id, "weapon": weapon},
            events,
        )
        self.revision += 1
        self.card = {
            "kind": "clear_jam",
            "title": "JAM CLEARED",
            "actor": self._actor(actor_id)["name"],
            "lines": [f"{weapon} is ready to fire"],
            "tone": "neutral",
            "duration_seconds": 5.0,
        }
        self.events = [deepcopy(event) for event in events]
        self.result = {"jam_cleared": True}
        return self.snapshot()

    def close_month(self, *, month: str | None = None) -> dict[str, Any]:
        """Close one game month and automatically bill every actor's Lifestyle.

        The book bills at the start of a month. Closing a month therefore pays
        for the upcoming month, which gives the requested end-of-month flow
        without changing the sourcebook's monthly cadence.
        """

        calendar = self.session.state.setdefault(
            "calendar", {"current_month": self.default_month, "closed_months": []}
        )
        closing_month = validate_month(month or str(calendar["current_month"]))
        if closing_month != str(calendar["current_month"]):
            raise ValueError(f"next month to close is {calendar['current_month']}")
        if closing_month in calendar.get("closed_months", []):
            raise ValueError(f"month already closed: {closing_month}")
        billed_month = next_month(closing_month)

        events: list[dict[str, Any]] = []
        lines: list[str] = []
        paid: list[str] = []
        unpaid: list[str] = []
        total_deducted = 0
        for actor_id, actor in self.session.state["actors"].items():
            profile = LIFESTYLES[str(actor["lifestyle"])]
            event = {
                "kind": "lifestyle_charged",
                "actor_id": actor_id,
                "month": billed_month,
                "lifestyle": profile.key,
                "amount": profile.monthly_cost,
            }
            if int(actor["cash"]) >= profile.monthly_cost:
                events.append(event)
                paid.append(actor_id)
                total_deducted += profile.monthly_cost
                remaining = int(actor["cash"]) - profile.monthly_cost
                lines.append(
                    f"{actor['name']}: {profile.label} -{profile.monthly_cost}eb ({remaining}eb left)"
                )
            else:
                events.append({**event, "kind": "lifestyle_unpaid"})
                unpaid.append(actor_id)
                lines.append(
                    f"{actor['name']}: {profile.label} {profile.monthly_cost}eb DUE (7-day grace)"
                )
        events.append(
            {
                "kind": "month_closed",
                "month": closing_month,
                "next_month": billed_month,
            }
        )
        self.session.record(
            {"kind": "month_end", "month": closing_month, "billed_month": billed_month},
            events,
        )
        self.revision += 1
        self.card = {
            "kind": "month_end",
            "title": f"{closing_month} CLOSED",
            "lines": lines,
            "tone": "miss" if unpaid else "neutral",
            "duration_seconds": 8.0,
        }
        self.events = [deepcopy(event) for event in events]
        self.result = {
            "closed_month": closing_month,
            "billed_month": billed_month,
            "total_deducted": total_deducted,
            "paid": paid,
            "unpaid": unpaid,
            "source_page": 377,
        }
        return self.snapshot()

    def undo(self) -> dict[str, Any]:
        inverse = [deepcopy(event) for event in self.session.log[-1].inverse]
        self.session.undo()
        self.revision += 1
        self.card = {
            "kind": "undo",
            "title": "UNDO",
            "lines": ["Previous action reversed."],
            "tone": "undo",
            "duration_seconds": 5.0,
        }
        self.events = inverse
        self.result = {"undone": True}
        return self.snapshot()

    def redo(self) -> dict[str, Any]:
        replayed = [deepcopy(event) for event in self.session.redo_log[-1].events]
        self.session.redo()
        self.revision += 1
        self.card = {
            "kind": "redo",
            "title": "REDO",
            "lines": ["Previous action applied again."],
            "tone": "neutral",
            "duration_seconds": 5.0,
        }
        self.events = replayed
        self.result = {"redone": True}
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
            "tone": "hit" if result.hit else "miss",
            "duration_seconds": 5.0,
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
            "attack_base": int(actor.get("attack_base", 0)),
            "evasion_base": int(actor.get("evasion_base", 0)),
            "selected_weapon": str(actor.get("selected_weapon", next(iter(actor["weapons"]), ""))),
            "skills": deepcopy(dict(actor.get("skills", {}))),
            "cash": int(actor["cash"]),
            "lifestyle": lifestyle_view(str(actor["lifestyle"])),
            "lifestyle_status": str(actor["lifestyle_status"]),
            "lifestyle_paid_through": actor.get("lifestyle_paid_through"),
            "lifestyle_balance_due": int(actor["lifestyle_balance_due"]),
            "lifestyle_grace_days": actor.get("lifestyle_grace_days"),
            "last_lifestyle_charge": int(actor["last_lifestyle_charge"]),
            "weapons": [self._weapon_view(actor_id, name, weapon) for name, weapon in actor["weapons"].items()],
        }

    def _weapon_view(self, actor_id: str, name: str, state: Mapping[str, Any]) -> dict[str, Any]:
        try:
            weapon = self._weapon(actor_id, name)
        except (KeyError, ValueError):
            return {
                "name": name,
                "ammo": int(state["ammo"]),
                "jammed": bool(state["jammed"]),
                "weapon_type": str(state.get("weapon_type", "unknown")),
                "damage_dice": int(state.get("damage_dice", 0)),
                "rof": int(state.get("rof", 1)),
                "magazine": int(state.get("magazine", state["ammo"])),
                "autofire_rating": state.get("autofire_rating"),
                "quality": str(state.get("quality", "standard")),
            }
        return {
            "name": name,
            "ammo": int(state["ammo"]),
            "jammed": bool(state["jammed"]),
            "weapon_type": weapon.weapon_type,
            "damage_dice": weapon.damage_dice,
            "rof": weapon.rof,
            "magazine": weapon.magazine,
            "autofire_rating": weapon.autofire_rating,
            "quality": weapon.quality,
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
            "events": deepcopy(self.events),
            "result": deepcopy(self.result),
            "covers": deepcopy(self.session.state.get("covers", {})),
            "calendar": deepcopy(self.session.state.get("calendar", {})),
            "lifestyles": [lifestyle_view(key) for key in LIFESTYLES],
        }


__all__ = ["Encounter"]
