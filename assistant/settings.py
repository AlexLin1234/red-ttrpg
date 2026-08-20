"""Non-secret helper settings.

The model tier lives here rather than in a campaign save, so a `.red` file
handed to another Game Master carries no model name to go stale. The API key is
never written here — only the vault holds it.
"""

from __future__ import annotations

import json

from assistant import paths
from assistant.agent import DEFAULT_TIER, MODELS

DEFAULTS: dict[str, object] = {
    "model_tier": DEFAULT_TIER,
    # The disclosure that retrieved excerpts leave the machine is shown until
    # the Game Master has acknowledged it once.
    "disclosure_accepted": False,
    "history_enabled": True,
}


def read() -> dict[str, object]:
    location = paths.settings_file()
    values = dict(DEFAULTS)
    if location.is_file():
        try:
            stored = json.loads(location.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return values
        if isinstance(stored, dict):
            for key in DEFAULTS:
                if key in stored:
                    values[key] = stored[key]
    if values["model_tier"] not in MODELS:
        values["model_tier"] = DEFAULT_TIER
    values["disclosure_accepted"] = bool(values["disclosure_accepted"])
    values["history_enabled"] = bool(values["history_enabled"])
    return values


def write(changes: dict[str, object]) -> dict[str, object]:
    values = read()
    for key, value in changes.items():
        if key in DEFAULTS and value is not None:
            values[key] = value
    if values["model_tier"] not in MODELS:
        values["model_tier"] = DEFAULT_TIER
    location = paths.settings_file()
    location.parent.mkdir(parents=True, exist_ok=True)
    temporary = location.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(values, indent=2), encoding="utf-8")
    temporary.replace(location)
    return read()


__all__ = ["DEFAULTS", "read", "write"]
