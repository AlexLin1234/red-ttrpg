"""Per-campaign question history, kept local.

The history is a convenience for one Game Master on one machine, so it lives in
application data rather than inside the portable `.red` file: a campaign handed
to another GM should not carry a transcript of what its author asked. Answers
are kept, retrieved book text is not.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from assistant import paths

MAX_ENTRIES = 100
_SAFE_ID = re.compile(r"[^A-Za-z0-9_-]")


def _file_for(campaign_id: str) -> Path:
    cleaned = _SAFE_ID.sub("", str(campaign_id))[:64] or "campaign"
    return paths.history_dir() / f"{cleaned}.json"


@dataclass(frozen=True, slots=True)
class Entry:
    asked_at: str
    question: str
    status: str
    answer: str
    citations: list[dict[str, object]]

    def as_dict(self) -> dict[str, object]:
        return {
            "asked_at": self.asked_at,
            "question": self.question,
            "status": self.status,
            "answer": self.answer,
            "citations": self.citations,
        }


def read(campaign_id: str) -> list[dict[str, object]]:
    location = _file_for(campaign_id)
    if not location.is_file():
        return []
    try:
        document = json.loads(location.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    entries = document.get("entries", [])
    return entries if isinstance(entries, list) else []


def _citations_of(answer: dict[str, object]) -> list[dict[str, object]]:
    citations = answer.get("citations", [])
    if not isinstance(citations, list):
        return []
    return [entry for entry in citations if isinstance(entry, dict)]


def append(campaign_id: str, question: str, answer: dict[str, object]) -> None:
    paths.history_dir().mkdir(parents=True, exist_ok=True)
    entry = Entry(
        asked_at=datetime.now(UTC).isoformat(timespec="seconds"),
        question=question,
        status=str(answer.get("status", "")),
        answer=str(answer.get("answer", "")),
        # answer is a dict[str, object] off the agent, so the value has to be
        # narrowed before it can be copied into a list.
        citations=_citations_of(answer),
    )
    entries = [entry.as_dict(), *read(campaign_id)][:MAX_ENTRIES]
    location = _file_for(campaign_id)
    temporary = location.with_suffix(".json.tmp")
    temporary.write_text(json.dumps({"entries": entries}, indent=2), encoding="utf-8")
    temporary.replace(location)


def clear(campaign_id: str) -> None:
    location = _file_for(campaign_id)
    if location.is_file():
        location.unlink()


__all__ = ["Entry", "MAX_ENTRIES", "append", "clear", "read"]
