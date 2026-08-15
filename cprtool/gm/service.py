"""Local FastAPI service for cited rules answers and GM-approved adjudication."""

from __future__ import annotations

import os
from dataclasses import asdict
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from cprtool.gm.agent import Agent, AnthropicAgent, OfflineAgent
from cprtool.gm.tools import GMTools
from cprtool.index.query import RulesIndex
from cprtool.rules.tables import JSONTables


class AskRequest(BaseModel):
    question: str = Field(min_length=2, max_length=2_000)
    book: str | None = None


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
) -> FastAPI:
    application = FastAPI(title="Cyberpunk RED Stream GM Tool", version="0.1.0")
    cached_agent = agent

    def current_agent() -> Agent:
        nonlocal cached_agent
        if cached_agent is None:
            cached_agent = build_agent(database, tables_path)
        return cached_agent

    @application.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @application.post("/ask", response_model=AskResponse)
    def ask(request: AskRequest) -> AskResponse:
        try:
            answer, citations = current_agent().ask(request.question, request.book)
            return AskResponse(answer=answer, citations=[CitationModel(**asdict(citation)) for citation in citations])
        except (FileNotFoundError, RuntimeError, ValueError, KeyError) as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc

    @application.post("/adjudicate", response_model=AdjudicateResponse)
    def adjudicate(request: AdjudicateRequest) -> AdjudicateResponse:
        try:
            result: dict[str, Any] = current_agent().adjudicate(request.description)
            return AdjudicateResponse(**result, requires_gm_approval=True)
        except (FileNotFoundError, RuntimeError, ValueError, KeyError) as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc

    return application


app = create_app()


__all__ = ["app", "build_agent", "create_app"]
