"""Persistent GM map images and normalized drawable zones."""

from __future__ import annotations

import json
import math
import os
import re
from pathlib import Path
from typing import Any, Mapping, Sequence

import pymupdf


_ZONE_ID = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
_COLOR = re.compile(r"^#[0-9A-Fa-f]{6}$")


class MapStore:
    """Store one active raster map and its polygon zones on local disk."""

    max_upload_bytes = 32 * 1024 * 1024
    max_pixels = 40_000_000

    def __init__(self, directory: str | Path = "data/maps") -> None:
        self.directory = Path(directory)
        self.image_path = self.directory / "active_map.png"
        self.manifest_path = self.directory / "active_map.json"
        self._state = self._load_state()

    def _load_state(self) -> dict[str, Any]:
        if self.manifest_path.is_file():
            try:
                state = json.loads(self.manifest_path.read_text(encoding="utf-8"))
                if isinstance(state, dict):
                    state.setdefault("zones", [])
                    state.setdefault("revision", 0)
                    return state
            except (OSError, ValueError):
                pass
        fallback = self.directory / "night_city_2045.png"
        if fallback.is_file():
            pixmap = pymupdf.Pixmap(fallback)
            return {
                "revision": 1,
                "image_file": fallback.name,
                "original_name": fallback.name,
                "width": pixmap.width,
                "height": pixmap.height,
                "zones": [],
            }
        return {"revision": 0, "zones": []}

    def manifest(self) -> dict[str, Any]:
        image = self.current_image()
        available = image is not None
        return {
            "available": available,
            "revision": int(self._state.get("revision", 0)),
            "original_name": self._state.get("original_name"),
            "width": int(self._state.get("width", 0)) if available else 0,
            "height": int(self._state.get("height", 0)) if available else 0,
            "image_url": (
                f"/map/image?revision={int(self._state.get('revision', 0))}"
                if available
                else None
            ),
            "zones": list(self._state.get("zones", [])),
        }

    def current_image(self) -> Path | None:
        image_file = self._state.get("image_file")
        if not isinstance(image_file, str):
            return None
        candidate = self.directory / Path(image_file).name
        return candidate if candidate.is_file() else None

    def upload(self, content: bytes, original_name: str) -> dict[str, Any]:
        if not content:
            raise ValueError("map upload is empty")
        if len(content) > self.max_upload_bytes:
            raise ValueError("map upload exceeds the 32 MB limit")
        try:
            source = pymupdf.Pixmap(content)
        except Exception as exc:
            raise ValueError("upload is not a supported raster image") from exc
        if source.width <= 0 or source.height <= 0:
            raise ValueError("map image has invalid dimensions")
        if source.width * source.height > self.max_pixels:
            raise ValueError("map image exceeds the 40 megapixel limit")
        pixmap = source
        if source.colorspace is None or source.colorspace.n != 3:
            pixmap = pymupdf.Pixmap(pymupdf.csRGB, source)

        self.directory.mkdir(parents=True, exist_ok=True)
        temporary = self.directory / "active_map.uploading.png"
        temporary.write_bytes(pixmap.tobytes("png"))
        os.replace(temporary, self.image_path)
        self._state = {
            "revision": int(self._state.get("revision", 0)) + 1,
            "image_file": self.image_path.name,
            "original_name": Path(original_name or "uploaded-map").name[:200],
            "width": pixmap.width,
            "height": pixmap.height,
            "zones": [],
        }
        self._save()
        return self.manifest()

    def replace_zones(self, zones: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
        if len(zones) > 100:
            raise ValueError("a map supports at most 100 zones")
        normalized: list[dict[str, Any]] = []
        used_ids: set[str] = set()
        for entry in zones:
            zone_id = str(entry.get("id", ""))
            if not _ZONE_ID.fullmatch(zone_id) or zone_id in used_ids:
                raise ValueError(f"invalid or duplicate zone id: {zone_id}")
            used_ids.add(zone_id)
            label = str(entry.get("label", "Zone")).strip()[:80] or "Zone"
            color = str(entry.get("color", "#00E5FF"))
            if not _COLOR.fullmatch(color):
                raise ValueError(f"{zone_id}: color must be #RRGGBB")
            opacity = float(entry.get("opacity", 0.24))
            if not math.isfinite(opacity) or not 0.0 <= opacity <= 1.0:
                raise ValueError(f"{zone_id}: opacity must be between 0 and 1")
            points = entry.get("points")
            if not isinstance(points, Sequence) or isinstance(points, (str, bytes)):
                raise ValueError(f"{zone_id}: points must be a list")
            if not 3 <= len(points) <= 100:
                raise ValueError(f"{zone_id}: zones need 3 to 100 points")
            clean_points: list[list[float]] = []
            for point in points:
                if (
                    not isinstance(point, Sequence)
                    or isinstance(point, (str, bytes))
                    or len(point) != 2
                ):
                    raise ValueError(f"{zone_id}: every point needs x and y")
                x, y = float(point[0]), float(point[1])
                if not math.isfinite(x) or not math.isfinite(y) or not (0 <= x <= 1 and 0 <= y <= 1):
                    raise ValueError(f"{zone_id}: points must use normalized coordinates")
                clean_points.append([round(x, 6), round(y, 6)])
            normalized.append(
                {
                    "id": zone_id,
                    "label": label,
                    "color": color.upper(),
                    "opacity": round(opacity, 3),
                    "points": clean_points,
                }
            )
        self._state["zones"] = normalized
        self._state["revision"] = int(self._state.get("revision", 0)) + 1
        self._save()
        return self.manifest()

    def _save(self) -> None:
        self.directory.mkdir(parents=True, exist_ok=True)
        temporary = self.directory / "active_map.uploading.json"
        temporary.write_text(json.dumps(self._state, indent=2), encoding="utf-8")
        os.replace(temporary, self.manifest_path)


__all__ = ["MapStore"]
