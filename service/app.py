"""Small persistent campaign API for cloud-hosted Redline sessions."""

from __future__ import annotations

import asyncio
import json
import os
import re
from copy import deepcopy
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from pydantic import BaseModel


def _lifestyle_table() -> tuple[dict[str, int], int]:
    """Read the one Lifestyle table both implementations bill from.

    The GDScript app closes the same month as this endpoint does, and the two
    used to carry separate copies of these numbers. They read one file now, and
    catalog/lifestyle_cases.json is checked by both suites, so a change that
    reaches only one of them fails rather than drifting quietly.
    """

    path = Path(__file__).resolve().parent.parent / "catalog" / "lifestyle.json"
    fallback = {"kibble": 100, "generic_prepak": 300, "good_prepak": 600, "fresh_food": 1500}
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return fallback, 7
    costs = {str(row["key"]): int(row["cost"]) for row in document.get("catalog", []) if isinstance(row, dict)}
    return costs or fallback, int(document.get("grace_days", 7))


LIFESTYLES, GRACE_DAYS = _lifestyle_table()
MONTH = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
STATE_PATH = Path(os.getenv("REDLINE_STATE", "/data/campaign.json"))
app = FastAPI(title="Redline campaign API")
clients: set[WebSocket] = set()
lock = asyncio.Lock()


class StateError(ValueError):
    """The stored campaign state cannot be used, and the reason is reportable.

    Its own class rather than a bare ValueError, so the handler below turns
    exactly these into a 422 and leaves an unrelated bug showing as a 500.
    """


class MonthEnd(BaseModel):
    month: str


def next_month(value: str) -> str:
    year, month = map(int, value.split("-"))
    return f"{year + (month == 12):04d}-{month % 12 + 1:02d}"


def _is_month(value: object) -> bool:
    return isinstance(value, str) and MONTH.fullmatch(value) is not None


def validate(state: dict) -> None:
    """Check everything the month-end roll then reads without a default.

    A hand-edited state file is a mistake to report, not a crash: every key the
    endpoints index directly is required here so the caller gets a sentence
    naming the problem instead of a 500.
    """

    if not _is_month(state.get("current_month", "")):
        raise StateError("current_month must use YYYY-MM")
    characters = state.get("characters", [])
    if not isinstance(characters, list):
        raise StateError("characters must be a list")
    for character in characters:
        if not isinstance(character, dict):
            raise StateError("every character must be an object")
        for key in ("id", "name"):
            if not isinstance(character.get(key), str) or not character[key]:
                raise StateError(f"every character needs a {key}")
        if character.get("lifestyle") not in LIFESTYLES:
            raise StateError(f"invalid Lifestyle ID for {character.get('name', 'character')}")
        if "cash" not in character:
            raise StateError(f"{character['name']} has no cash")
        for key in ("cash", "lifestyle_balance_due"):
            value = character.get(key, 0)
            if isinstance(value, bool) or not isinstance(value, int) or value < 0:
                raise StateError(f"{key} must be a non-negative integer")
        paid = character.get("lifestyle_paid_through")
        if paid is not None and not _is_month(paid):
            raise StateError("lifestyle_paid_through must use YYYY-MM")


def load() -> dict:
    try:
        state = json.loads(STATE_PATH.read_text())
    except OSError as exc:
        raise StateError(f"the campaign state file could not be read: {exc.strerror}") from exc
    except json.JSONDecodeError as exc:
        raise StateError(f"the campaign state file is not valid JSON: {exc.msg}") from exc
    if not isinstance(state, dict):
        raise StateError("the campaign state file must hold an object")
    validate(state)
    for key in ("characters", "closed_months", "undo", "redo"):
        if not isinstance(state.setdefault(key, []), list):
            raise StateError(f"{key} must be a list")
    return state


def save(state: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    temporary = STATE_PATH.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2))
    temporary.replace(STATE_PATH)


async def broadcast(state: dict) -> None:
    for client in list(clients):
        try:
            await client.send_json({"type": "campaign_state", "state": state})
        except Exception:
            clients.discard(client)


@app.exception_handler(StateError)
async def unreadable_state(_request: Request, error: StateError) -> JSONResponse:
    """A bad state file is the operator's problem, so name it rather than 500."""

    return JSONResponse(status_code=422, content={"detail": str(error)})


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.post("/encounter/month-end")
async def month_end(request: MonthEnd) -> dict:
    async with lock:
        state = load()
        if request.month != state["current_month"]:
            raise HTTPException(409, "requested month is not the current month")
        if request.month in state["closed_months"]:
            raise HTTPException(409, "month already closed")
        before = deepcopy({key: value for key, value in state.items() if key not in ("undo", "redo")})
        billed = next_month(request.month)
        results, warnings = [], []
        for character in state["characters"]:
            cost = LIFESTYLES[character["lifestyle"]]
            paid = character["cash"] >= cost
            if paid:
                character["cash"] -= cost
                character.update(
                    lifestyle_status="paid",
                    lifestyle_paid_through=billed,
                    lifestyle_balance_due=0,
                    lifestyle_grace_days=0,
                    last_lifestyle_charge=cost,
                )
            else:
                character.update(
                    lifestyle_status="unpaid",
                    lifestyle_balance_due=cost,
                    lifestyle_grace_days=GRACE_DAYS,
                    last_lifestyle_charge=0,
                )
                warnings.append(f"{character['name']}: payment failed; {GRACE_DAYS}-day grace period started")
            results.append(
                {
                    "character_id": character["id"],
                    "name": character["name"],
                    "deducted": cost if paid else 0,
                    "balance_due": 0 if paid else cost,
                    "status": "paid" if paid else "unpaid",
                }
            )
        state["closed_months"].append(request.month)
        state["current_month"] = billed
        state["undo"].append(before)
        state["redo"] = []
        save(state)
        await broadcast(state)
        return {
            "closed_month": request.month,
            "new_month": billed,
            "results": results,
            "total_deducted": sum(item["deducted"] for item in results),
            "warnings": warnings,
        }


@app.post("/encounter/month-end/undo")
async def undo_month_end() -> dict:
    async with lock:
        state = load()
        if not state["undo"]:
            raise HTTPException(409, "nothing to undo")
        history, redo = state["undo"], state["redo"]
        current = deepcopy({key: value for key, value in state.items() if key not in ("undo", "redo")})
        restored = history.pop()
        if not isinstance(restored, dict):
            raise StateError("the undo history holds something that is not a campaign state")
        restored.update(undo=history, redo=redo + [current])
        validate(restored)
        save(restored)
        await broadcast(restored)
        return restored


@app.post("/encounter/month-end/redo")
async def redo_month_end() -> dict:
    async with lock:
        state = load()
        if not state["redo"]:
            raise HTTPException(409, "nothing to redo")
        history, redo = state["undo"], state["redo"]
        current = deepcopy({key: value for key, value in state.items() if key not in ("undo", "redo")})
        restored = redo.pop()
        if not isinstance(restored, dict):
            raise StateError("the redo history holds something that is not a campaign state")
        restored.update(undo=history + [current], redo=redo)
        validate(restored)
        save(restored)
        await broadcast(restored)
        return restored


@app.websocket("/ws")
async def websocket(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        state = load()
    except StateError as error:
        # Nothing was registered yet, so there is nothing to leave behind.
        await websocket.close(code=1011, reason=str(error)[:120])
        return
    clients.add(websocket)
    # Every exit runs the discard: a socket that dies inside the first send, or
    # on anything other than a clean disconnect, would otherwise stay in the
    # broadcast set for the life of the process.
    try:
        await websocket.send_json({"type": "campaign_state", "state": state})
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        pass
    finally:
        clients.discard(websocket)
