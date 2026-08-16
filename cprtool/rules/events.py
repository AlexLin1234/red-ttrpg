"""Reversible event application and session history."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass, field
from typing import Any, Final, Iterable, Mapping


EVENT_KINDS: Final[frozenset[str]] = frozenset(
    {
        "ammo_spent",
        "weapon_jammed",
        "attack_missed",
        "cover_damaged",
        "cover_set",
        "armor_ablated",
        "damage_taken",
        "critical_injury",
        "seriously_wounded",
        "death_save_due",
    }
)


def _actor(state: dict[str, Any], actor_id: str) -> dict[str, Any]:
    try:
        return state["actors"][actor_id]
    except KeyError as exc:
        raise KeyError(f"unknown actor: {actor_id}") from exc


def _apply_one(state: dict[str, Any], event: Mapping[str, Any]) -> dict[str, Any]:
    kind = str(event["kind"])
    if kind == "noop" or kind == "attack_missed":
        return {"kind": "noop"}
    if kind in {"ammo_spent", "ammo_restored"}:
        actor = _actor(state, str(event["actor_id"]))
        weapon = actor["weapons"][str(event["weapon"])]
        amount = int(event["amount"])
        delta = -amount if kind == "ammo_spent" else amount
        if weapon["ammo"] + delta < 0:
            raise ValueError("event would make ammo negative")
        weapon["ammo"] += delta
        return {**event, "kind": "ammo_restored" if kind == "ammo_spent" else "ammo_spent"}
    if kind in {"weapon_jammed", "weapon_unjammed"}:
        actor = _actor(state, str(event["actor_id"]))
        weapon = actor["weapons"][str(event["weapon"])]
        previous = bool(weapon.get("jammed", False))
        weapon["jammed"] = kind == "weapon_jammed"
        return {
            "kind": "weapon_jammed" if previous else "weapon_unjammed",
            "actor_id": event["actor_id"],
            "weapon": event["weapon"],
        }
    target = _actor(state, str(event.get("target_id", "")))
    if kind == "cover_set":
        previous = int(target.get("cover_hp", 0))
        target_cover_id_existed = "cover_id" in target
        previous_id = target.get("cover_id")
        cover_id = event.get("cover_id")
        covers_existed = "covers" in state
        covers = state.setdefault("covers", {})
        cover_existed = cover_id is not None and str(cover_id) in covers
        previous_cover_hp = int(covers[str(cover_id)]) if cover_existed else None
        target["cover_hp"] = int(event["hp"])
        target["cover_id"] = cover_id
        if target["cover_hp"] < 0:
            raise ValueError("cover HP cannot be negative")
        if cover_id is not None:
            covers[str(cover_id)] = target["cover_hp"]
        return {
            "kind": "cover_restored",
            "target_id": event["target_id"],
            "hp": previous,
            "cover_id": previous_id,
            "target_cover_id_existed": target_cover_id_existed,
            "affected_cover_id": cover_id,
            "cover_existed": cover_existed,
            "previous_cover_hp": previous_cover_hp,
            "covers_existed": covers_existed,
        }
    if kind == "cover_restored":
        target["cover_hp"] = int(event["hp"])
        if event.get("target_cover_id_existed", False):
            target["cover_id"] = event.get("cover_id")
        else:
            target.pop("cover_id", None)
        covers = state.setdefault("covers", {})
        affected_cover_id = event.get("affected_cover_id")
        if affected_cover_id is not None:
            key = str(affected_cover_id)
            if event.get("cover_existed", False):
                covers[key] = int(event["previous_cover_hp"])
            else:
                covers.pop(key, None)
        if not event.get("covers_existed", True) and not covers:
            state.pop("covers", None)
        return {"kind": "noop"}
    if kind in {"cover_damaged", "cover_repaired"}:
        amount = int(event["amount"])
        cover_id = event.get("cover_id")
        covers = state.setdefault("covers", {}) if cover_id is not None else state.get("covers", {})
        previous = (
            int(covers[str(cover_id)])
            if cover_id is not None and str(cover_id) in covers
            else int(target.get("cover_hp", 0))
        )
        target["cover_hp"] = (
            max(0, previous - amount) if kind == "cover_damaged" else previous + amount
        )
        if cover_id is not None:
            covers[str(cover_id)] = target["cover_hp"]
        actual = previous - target["cover_hp"] if kind == "cover_damaged" else amount
        inverse = {
            "kind": "cover_repaired" if kind == "cover_damaged" else "cover_damaged",
            "target_id": event["target_id"],
            "amount": actual,
        }
        if event.get("cover_id") is not None:
            inverse["cover_id"] = event["cover_id"]
        return inverse
    if kind in {"armor_ablated", "armor_restored"}:
        location = str(event["location"])
        amount = int(event.get("amount", 1))
        armor = target.setdefault("armor", {"body": 0, "head": 0})
        previous = int(armor[location])
        armor[location] = max(0, previous - amount) if kind == "armor_ablated" else previous + amount
        actual = previous - armor[location] if kind == "armor_ablated" else amount
        return {"kind": "armor_restored" if kind == "armor_ablated" else "armor_ablated", "target_id": event["target_id"], "location": location, "amount": actual}
    if kind in {"damage_taken", "damage_healed"}:
        amount = int(event["amount"])
        previous = int(target["hp"])
        target["hp"] = previous - amount if kind == "damage_taken" else min(int(target["max_hp"]), previous + amount)
        actual = previous - target["hp"] if kind == "damage_taken" else target["hp"] - previous
        return {"kind": "damage_healed" if kind == "damage_taken" else "damage_taken", "target_id": event["target_id"], "amount": actual}
    if kind in {"critical_injury", "critical_injury_removed"}:
        injuries = target.setdefault("critical_injuries", [])
        injury = str(event["injury"])
        if kind == "critical_injury":
            injuries.append(injury)
            return {"kind": "critical_injury_removed", "target_id": event["target_id"], "injury": injury}
        injuries.remove(injury)
        return {"kind": "critical_injury", "target_id": event["target_id"], "location": event.get("location", "body"), "injury": injury, "rolls": event.get("rolls", ())}
    if kind in {"seriously_wounded", "wound_state_restored"}:
        previous = str(target.get("wound_state", "unhurt"))
        target["wound_state"] = "seriously_wounded" if kind == "seriously_wounded" else str(event["state"])
        return {"kind": "wound_state_restored", "target_id": event["target_id"], "state": previous}
    if kind in {"death_save_due", "death_save_cleared"}:
        previous = bool(target.get("death_save_due", False))
        target["death_save_due"] = kind == "death_save_due"
        return {"kind": "death_save_due" if previous else "death_save_cleared", "target_id": event["target_id"]}
    raise ValueError(f"unsupported event kind: {kind}")


def apply(state: Mapping[str, Any], events: Iterable[Mapping[str, Any]]) -> tuple[dict[str, Any], tuple[dict[str, Any], ...]]:
    """Apply events atomically and return new state plus ready-to-run inverses."""

    new_state = deepcopy(dict(state))
    inverses: list[dict[str, Any]] = []
    for event in events:
        inverses.append(_apply_one(new_state, event))
    inverses.reverse()
    return new_state, tuple(inverses)


@dataclass(frozen=True, slots=True)
class LogEntry:
    action: Mapping[str, Any]
    events: tuple[Mapping[str, Any], ...]
    inverse: tuple[Mapping[str, Any], ...]


@dataclass(slots=True)
class Session:
    state: dict[str, Any]
    log: list[LogEntry] = field(default_factory=list)
    redo_log: list[LogEntry] = field(default_factory=list)

    def record(self, action: Mapping[str, Any], events: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
        event_tuple = tuple(deepcopy(tuple(events)))
        new_state, inverse = apply(self.state, event_tuple)
        self.state = new_state
        self.log.append(LogEntry(deepcopy(dict(action)), event_tuple, inverse))
        self.redo_log.clear()
        return deepcopy(self.state)

    def undo(self) -> dict[str, Any]:
        if not self.log:
            raise IndexError("nothing to undo")
        entry = self.log.pop()
        self.state, _ = apply(self.state, entry.inverse)
        self.redo_log.append(entry)
        return deepcopy(self.state)

    def redo(self) -> dict[str, Any]:
        if not self.redo_log:
            raise IndexError("nothing to redo")
        entry = self.redo_log.pop()
        self.state, inverse = apply(self.state, entry.events)
        self.log.append(LogEntry(entry.action, entry.events, inverse))
        return deepcopy(self.state)


__all__ = ["EVENT_KINDS", "LogEntry", "Session", "apply"]
