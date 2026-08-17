"""Small persistent campaign API for cloud-hosted Redline sessions."""
from __future__ import annotations

import asyncio
import json
import os
import re
from copy import deepcopy
from pathlib import Path

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel

LIFESTYLES = {"kibble": 100, "generic_prepak": 300, "good_prepak": 600, "fresh_food": 1500}
MONTH = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
STATE_PATH = Path(os.getenv("REDLINE_STATE", "/data/campaign.json"))
app = FastAPI(title="Redline campaign API")
clients: set[WebSocket] = set()
lock = asyncio.Lock()


class MonthEnd(BaseModel):
    month: str


def next_month(value: str) -> str:
    year, month = map(int, value.split("-"))
    return f"{year + (month == 12):04d}-{month % 12 + 1:02d}"


def validate(state: dict) -> None:
    if not MONTH.fullmatch(state.get("current_month", "")):
        raise ValueError("current_month must use YYYY-MM")
    for character in state.get("characters", []):
        if character.get("lifestyle") not in LIFESTYLES:
            raise ValueError(f"invalid Lifestyle ID for {character.get('name', 'character')}")
        for key in ("cash", "lifestyle_balance_due"):
            if not isinstance(character.get(key, 0), int) or character.get(key, 0) < 0:
                raise ValueError(f"{key} must be a non-negative integer")
        paid = character.get("lifestyle_paid_through")
        if paid is not None and not MONTH.fullmatch(paid):
            raise ValueError("lifestyle_paid_through must use YYYY-MM")


def load() -> dict:
    state = json.loads(STATE_PATH.read_text())
    validate(state)
    state.setdefault("closed_months", [])
    state.setdefault("undo", [])
    state.setdefault("redo", [])
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
                character.update(lifestyle_status="paid", lifestyle_paid_through=billed,
                                 lifestyle_balance_due=0, lifestyle_grace_days=0,
                                 last_lifestyle_charge=cost)
            else:
                character.update(lifestyle_status="unpaid", lifestyle_balance_due=cost,
                                 lifestyle_grace_days=7, last_lifestyle_charge=0)
                warnings.append(f"{character['name']}: payment failed; seven-day grace period started")
            results.append({"character_id": character["id"], "name": character["name"],
                            "deducted": cost if paid else 0, "balance_due": 0 if paid else cost,
                            "status": "paid" if paid else "unpaid"})
        state["closed_months"].append(request.month)
        state["current_month"] = billed
        state["undo"].append(before)
        state["redo"] = []
        save(state)
        await broadcast(state)
        return {"closed_month": request.month, "new_month": billed, "results": results,
                "total_deducted": sum(item["deducted"] for item in results), "warnings": warnings}


@app.post("/encounter/month-end/undo")
async def undo_month_end() -> dict:
    async with lock:
        state = load()
        if not state["undo"]:
            raise HTTPException(409, "nothing to undo")
        history, redo = state["undo"], state["redo"]
        current = deepcopy({key: value for key, value in state.items() if key not in ("undo", "redo")})
        restored = history.pop()
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
        restored.update(undo=history + [current], redo=redo)
        validate(restored)
        save(restored)
        await broadcast(restored)
        return restored


@app.websocket("/ws")
async def websocket(websocket: WebSocket) -> None:
    await websocket.accept()
    clients.add(websocket)
    await websocket.send_json({"type": "campaign_state", "state": load()})
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        clients.discard(websocket)
