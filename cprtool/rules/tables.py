"""Interfaces and JSON adapter for operator-verified rules tables."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Protocol


@dataclass(frozen=True, slots=True)
class CriticalInjuryRef:
    name: str
    page: int


@dataclass(frozen=True, slots=True)
class WeaponProfile:
    name: str
    range_type: str
    skill: str
    damage_dice: int
    magazine: int | None
    rof: int
    hands: int
    concealable: bool
    autofire_rating: int | None
    page: int


@dataclass(frozen=True, slots=True)
class ArmorProfile:
    name: str
    sp: int
    penalty: Mapping[str, int]
    page: int


class Tables(Protocol):
    def ranged_dv(self, weapon_type: str, distance_m: float) -> int: ...

    def critical_injury(self, location: str, roll: int) -> CriticalInjuryRef: ...

    def autofire_dv(self, weapon_type: str, distance_m: float) -> int: ...

    def autofire_multiplier(self, margin: int, rating: int | None) -> int: ...


class JSONTables:
    """Read validated, operator-owned tables from a local JSON file."""

    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)
        with self.path.open("r", encoding="utf-8") as handle:
            self._data: Mapping[str, Any] = json.load(handle)

    def ranged_dv(self, weapon_type: str, distance_m: float) -> int:
        if distance_m < 0:
            raise ValueError("distance_m cannot be negative")
        try:
            bands = self._data["ranged_dv"][weapon_type]
        except KeyError as exc:
            raise KeyError(f"unknown weapon type: {weapon_type}") from exc
        for band in bands:
            if float(band["min_m"]) <= distance_m <= float(band["max_m"]):
                dv = band.get("dv")
                if dv is None:
                    break
                return int(dv)
        raise ValueError(f"{weapon_type} has no valid range band at {distance_m} m")

    def autofire_dv(self, weapon_type: str, distance_m: float) -> int:
        if distance_m < 0:
            raise ValueError("distance_m cannot be negative")
        try:
            bands = self._data["autofire_dv"][weapon_type]
        except KeyError as exc:
            raise KeyError(f"weapon type does not support autofire: {weapon_type}") from exc
        for band in bands:
            if float(band["min_m"]) <= distance_m <= float(band["max_m"]):
                return int(band["dv"])
        raise ValueError(f"{weapon_type} has no autofire range band at {distance_m} m")

    def autofire_multiplier(self, margin: int, rating: int | None) -> int:
        if margin < 1:
            raise ValueError("autofire margin must be positive")
        if rating is None or rating < 1:
            raise ValueError("autofire rating must be positive")
        return min(margin, rating)

    def weapon(self, name: str) -> WeaponProfile:
        try:
            entry = self._data["weapons"][name]
        except KeyError as exc:
            raise KeyError(f"unknown weapon: {name}") from exc
        return WeaponProfile(
            name=name,
            range_type=str(entry["range_type"]),
            skill=str(entry["skill"]),
            damage_dice=int(entry["damage_dice"]),
            magazine=None if entry["magazine"] is None else int(entry["magazine"]),
            rof=int(entry["rof"]),
            hands=int(entry["hands"]),
            concealable=bool(entry["concealable"]),
            autofire_rating=None if entry.get("autofire_rating") is None else int(entry["autofire_rating"]),
            page=int(entry["page"]),
        )

    def armor(self, name: str) -> ArmorProfile:
        try:
            entry = self._data["armor"][name]
        except KeyError as exc:
            raise KeyError(f"unknown armor: {name}") from exc
        return ArmorProfile(name=name, sp=int(entry["sp"]), penalty=dict(entry["penalty"]), page=int(entry["page"]))

    def aimed_shot(self, location: str) -> Mapping[str, Any]:
        try:
            return dict(self._data["aimed_shots"][location])
        except KeyError as exc:
            raise KeyError(f"unknown aimed-shot location: {location}") from exc

    def cover(self, example: str) -> Mapping[str, Any]:
        try:
            return dict(self._data["cover"][example])
        except KeyError as exc:
            raise KeyError(f"unknown cover example: {example}") from exc

    def critical_injury(self, location: str, roll: int) -> CriticalInjuryRef:
        if location not in {"body", "head"}:
            raise ValueError(f"invalid injury location: {location}")
        if not 2 <= roll <= 12:
            raise ValueError("critical injury roll must be between 2 and 12")
        try:
            entry = self._data["critical_injuries"][location][str(roll)]
        except KeyError as exc:
            raise KeyError(f"missing {location} critical injury roll {roll}") from exc
        return CriticalInjuryRef(name=str(entry["name"]), page=int(entry["page"]))


__all__ = ["ArmorProfile", "CriticalInjuryRef", "JSONTables", "Tables", "WeaponProfile"]
