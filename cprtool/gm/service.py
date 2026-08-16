"""Local FastAPI service for cited rules answers and GM-approved adjudication."""

from __future__ import annotations

import os
from contextlib import contextmanager
from dataclasses import asdict
from pathlib import Path
from typing import Any, Iterator, Literal

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field

from cprtool.gm.agent import Agent, AnthropicAgent, OfflineAgent
from cprtool.gm.encounter import Encounter
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


class AttackCommand(BaseModel):
    attacker_id: str
    target_id: str
    weapon: str
    distance_m: float = Field(ge=0)
    location: Literal["body", "head"] = "body"
    mode: Literal["single", "aimed", "autofire"] = "single"
    modifiers: int = 0
    contested: bool = False


class ReloadCommand(BaseModel):
    actor_id: str
    weapon: str
    amount: int | None = None


class JamCommand(BaseModel):
    actor_id: str
    weapon: str


class ViewerHub:
    """Fan out encounter snapshots to every attached viewer."""

    def __init__(self) -> None:
        self.clients: set[WebSocket] = set()

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self.clients.add(websocket)

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
) -> FastAPI:
    application = FastAPI(title="Cyberpunk RED Stream GM Tool", version="0.1.0")
    application.state.viewers = ViewerHub()
    cached_agent = agent
    cached_encounter = encounter

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

    @application.post("/ask", response_model=AskResponse)
    async def ask(request: AskRequest) -> AskResponse:
        try:
            answer, citations = current_agent().ask(request.question, request.book)
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
            snapshot = current_encounter().load(request.actors)
        return await publish(snapshot)

    @application.post("/encounter/attack")
    async def attack(command: AttackCommand) -> dict[str, Any]:
        with _domain_errors():
            snapshot = current_encounter().attack(**command.model_dump())
        return await publish(snapshot)

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
        await hub.connect(websocket)
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
