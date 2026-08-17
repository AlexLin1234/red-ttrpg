"""Local FastAPI service for cited rules answers and GM-approved adjudication."""

from __future__ import annotations

import asyncio
import os
from contextlib import contextmanager
from dataclasses import asdict
from pathlib import Path
from typing import Any, Iterator, Literal
from urllib.parse import urlsplit

from fastapi import FastAPI, HTTPException, Query, Request, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field
from starlette.responses import FileResponse
from starlette.concurrency import run_in_threadpool

from cprtool.gm.agent import Agent, AnthropicAgent, OfflineAgent
from cprtool.gm.encounter import Encounter
from cprtool.gm.maps import MapStore
from cprtool.gm.tools import GMTools
from cprtool.index.query import RulesIndex
from cprtool.rules.tables import JSONTables


class AskRequest(BaseModel):
    question: str = Field(min_length=2, max_length=2_000)
    book: str | None = None
    broadcast: bool = False


class CitationModel(BaseModel):
    book: str
    section: str
    page_start: int
    page_end: int


class AskResponse(BaseModel):
    answer: str
    citations: list[CitationModel]


class AdjudicateRequest(BaseModel):
    description: str = Field(min_length=3, max_length=2_000)


class AdjudicateResponse(BaseModel):
    suggested_dv: int
    skill: str
    reasoning: str
    citations: list[CitationModel]
    requires_gm_approval: bool = True


class EncounterRequest(BaseModel):
    actors: dict[str, dict[str, Any]]
    current_month: str | None = Field(default=None, pattern=r"^\d{4}-(0[1-9]|1[0-2])$")


class AttackCommand(BaseModel):
    attacker_id: str
    target_id: str
    weapon: str
    distance_m: float = Field(ge=0, allow_inf_nan=False)
    location: Literal["body", "head"] = "body"
    mode: Literal["single", "aimed", "autofire"] = "single"
    modifiers: int = 0
    contested: bool = False
    cover_hp: int | None = Field(default=None, ge=0)
    cover_id: str | None = Field(default=None, max_length=200)


class ReloadCommand(BaseModel):
    actor_id: str
    weapon: str
    amount: int | None = None


class JamCommand(BaseModel):
    actor_id: str
    weapon: str


class MonthEndCommand(BaseModel):
    month: str | None = Field(default=None, pattern=r"^\d{4}-(0[1-9]|1[0-2])$")


class MapZone(BaseModel):
    id: str = Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    label: str = Field(default="Zone", min_length=1, max_length=80)
    color: str = Field(default="#00E5FF", pattern=r"^#[0-9A-Fa-f]{6}$")
    opacity: float = Field(default=0.24, ge=0, le=1, allow_inf_nan=False)
    points: list[tuple[float, float]] = Field(min_length=3, max_length=100)


class MapZonesCommand(BaseModel):
    zones: list[MapZone] = Field(default_factory=list, max_length=100)


class ViewerHub:
    """Fan out encounter snapshots to every attached viewer."""

    def __init__(self, max_clients: int = 8) -> None:
        self.clients: set[WebSocket] = set()
        self.max_clients = max_clients
        self._admission_lock = asyncio.Lock()

    async def connect(self, websocket: WebSocket) -> bool:
        origin = websocket.headers.get("origin")
        try:
            origin_host = urlsplit(origin).hostname if origin else None
        except ValueError:
            origin_host = "invalid"
        if origin and origin_host not in {"127.0.0.1", "localhost", "::1"}:
            await websocket.close(code=1008, reason="viewer origin is not allowed")
            return False
        async with self._admission_lock:
            if len(self.clients) >= self.max_clients:
                await websocket.close(code=1013, reason="viewer capacity reached")
                return False
            await websocket.accept()
            self.clients.add(websocket)
        return True

    def disconnect(self, websocket: WebSocket) -> None:
        self.clients.discard(websocket)

    async def broadcast(self, message: dict[str, Any]) -> None:
        for websocket in list(self.clients):
            try:
                await websocket.send_json(message)
            except Exception:  # a viewer that dropped mid-send must not fail the GM's action
                self.disconnect(websocket)


@contextmanager
def _domain_errors() -> Iterator[None]:
    """Map encounter errors onto the status codes the GM console expects."""

    try:
        yield
    except IndexError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except (KeyError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=str(exc.args[0]) if exc.args else str(exc)) from exc
    except FileNotFoundError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


def build_agent(database: str | Path, tables_path: str | Path) -> Agent:
    tools = GMTools(RulesIndex(database), JSONTables(tables_path))
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if api_key:
        model = os.getenv("CPR_ANTHROPIC_MODEL")
        if not model:
            raise RuntimeError("CPR_ANTHROPIC_MODEL is required when ANTHROPIC_API_KEY is set")
        return AnthropicAgent(tools, api_key, model)
    return OfflineAgent(tools)


def create_app(
    *,
    database: str | Path = "data/rules.db",
    tables_path: str | Path = "cprtool/rules/tables.json",
    agent: Agent | None = None,
    encounter: Encounter | None = None,
    map_directory: str | Path = "data/maps",
) -> FastAPI:
    application = FastAPI(title="Cyberpunk RED Stream GM Tool", version="0.1.0")
    application.state.viewers = ViewerHub()
    cached_agent = agent
    cached_encounter = encounter
    map_store = MapStore(map_directory)

    def current_agent() -> Agent:
        nonlocal cached_agent
        if cached_agent is None:
            cached_agent = build_agent(database, tables_path)
        return cached_agent

    def current_encounter() -> Encounter:
        nonlocal cached_encounter
        if cached_encounter is None:
            cached_encounter = Encounter(JSONTables(tables_path))
        return cached_encounter

    async def publish(snapshot: dict[str, Any]) -> dict[str, Any]:
        await application.state.viewers.broadcast(snapshot)
        return snapshot

    @application.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @application.get("/map")
    def read_map() -> dict[str, Any]:
        return map_store.manifest()

    @application.get("/map/image")
    def read_map_image() -> FileResponse:
        image = map_store.current_image()
        if image is None:
            raise HTTPException(status_code=404, detail="no map image has been uploaded")
        return FileResponse(image, media_type="image/png", headers={"Cache-Control": "no-store"})

    @application.put("/map/image")
    async def upload_map_image(
        request: Request,
        filename: str = Query(default="uploaded-map", min_length=1, max_length=200),
    ) -> dict[str, Any]:
        content = bytearray()
        async for chunk in request.stream():
            content.extend(chunk)
            if len(content) > map_store.max_upload_bytes:
                raise HTTPException(status_code=413, detail="map upload exceeds the 32 MB limit")
        with _domain_errors():
            manifest = map_store.upload(bytes(content), filename)
        await application.state.viewers.broadcast({"type": "map", "map": manifest})
        return manifest

    @application.put("/map/zones")
    async def replace_map_zones(command: MapZonesCommand) -> dict[str, Any]:
        with _domain_errors():
            manifest = map_store.replace_zones(
                [zone.model_dump(mode="json") for zone in command.zones]
            )
        await application.state.viewers.broadcast({"type": "map", "map": manifest})
        return manifest

    @application.post("/ask", response_model=AskResponse)
    async def ask(request: AskRequest) -> AskResponse:
        try:
            answer, citations = await run_in_threadpool(
                current_agent().ask,
                request.question,
                request.book,
            )
        except (FileNotFoundError, RuntimeError, ValueError, KeyError) as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        citation_models = [CitationModel(**asdict(citation)) for citation in citations]
        if request.broadcast:
            await application.state.viewers.broadcast(
                {
                    "type": "rules",
                    "question": request.question,
                    "answer": answer,
                    "citations": [citation.model_dump() for citation in citation_models],
                }
            )
        return AskResponse(answer=answer, citations=citation_models)

    @application.post("/adjudicate", response_model=AdjudicateResponse)
    def adjudicate(request: AdjudicateRequest) -> AdjudicateResponse:
        try:
            result: dict[str, Any] = current_agent().adjudicate(request.description)
            return AdjudicateResponse(**result, requires_gm_approval=True)
        except (FileNotFoundError, RuntimeError, ValueError, KeyError) as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc

    @application.get("/encounter")
    def read_encounter() -> dict[str, Any]:
        with _domain_errors():
            return current_encounter().snapshot()

    @application.post("/encounter")
    async def load_encounter(request: EncounterRequest) -> dict[str, Any]:
        with _domain_errors():
            snapshot = current_encounter().load(
                request.actors,
                current_month=request.current_month,
            )
        return await publish(snapshot)

    @application.post("/encounter/attack")
    async def attack(command: AttackCommand) -> dict[str, Any]:
        with _domain_errors():
            snapshot = current_encounter().attack(**command.model_dump())
        return await publish(snapshot)

    @application.post("/resolve")
    async def resolve(command: AttackCommand) -> dict[str, Any]:
        """Compatibility route matching the implementation-plan contract."""

        return await attack(command)

    @application.post("/encounter/reload")
    async def reload_weapon(command: ReloadCommand) -> dict[str, Any]:
        with _domain_errors():
            snapshot = current_encounter().reload(**command.model_dump())
        return await publish(snapshot)

    @application.post("/encounter/clear-jam")
    async def clear_jam(command: JamCommand) -> dict[str, Any]:
        with _domain_errors():
            snapshot = current_encounter().clear_jam(**command.model_dump())
        return await publish(snapshot)

    @application.post("/encounter/month-end")
    async def close_month(command: MonthEndCommand) -> dict[str, Any]:
        with _domain_errors():
            snapshot = current_encounter().close_month(month=command.month)
        return await publish(snapshot)

    @application.post("/encounter/undo")
    async def undo() -> dict[str, Any]:
        with _domain_errors():
            snapshot = current_encounter().undo()
        return await publish(snapshot)

    @application.post("/encounter/redo")
    async def redo() -> dict[str, Any]:
        with _domain_errors():
            snapshot = current_encounter().redo()
        return await publish(snapshot)

    @application.websocket("/viewer")
    async def viewer(websocket: WebSocket) -> None:
        hub: ViewerHub = application.state.viewers
        if not await hub.connect(websocket):
            return
        try:
            await websocket.send_json(current_encounter().snapshot())
        except (FileNotFoundError, KeyError, ValueError) as exc:
            await websocket.send_json({"type": "error", "detail": str(exc)})
        try:
            while True:
                # The viewer is display-only; reading keeps the socket alive and
                # detects a closed OBS source promptly.
                await websocket.receive_text()
        except WebSocketDisconnect:
            hub.disconnect(websocket)
        except Exception:
            hub.disconnect(websocket)

    return application


app = create_app()


__all__ = ["ViewerHub", "app", "build_agent", "create_app"]
