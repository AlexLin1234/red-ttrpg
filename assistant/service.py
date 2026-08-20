"""The loopback API Godot talks to.

Two things make this safe to run beside a game: it binds to the loopback
interface only, and it requires a session token that Godot generates fresh at
launch and passes over the helper's standard input. Nothing on the LAN can reach
it, and nothing else on the machine can use it without the token.

Every response is a plain JSON contract, and every error is passed through the
redactor before it leaves, so neither the Game Master's API key nor a line of
their rulebook can escape through an error message.
"""

from __future__ import annotations

import secrets
import threading
from collections.abc import AsyncIterator, Callable
from concurrent.futures import Future, ThreadPoolExecutor
from contextlib import asynccontextmanager
from typing import Any

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from assistant import __version__, credentials, history, paths, prompts, settings
from assistant.agent import MODELS, AnswerError, RulesAssistant
from assistant.index import ChunkIndex
from assistant.library import Book, LibraryError, RulebookLibrary
from assistant.redaction import safe_error
from assistant.retrieval import MAX_QUESTION_CHARS, Retriever

TOKEN_HEADER = "X-Redline-Token"
MAX_PATH_LENGTH = 4_096


class ImportRequest(BaseModel):
    path: str = Field(min_length=1, max_length=MAX_PATH_LENGTH)
    label: str = Field(default="", max_length=120)


class LabelRequest(BaseModel):
    label: str = Field(min_length=1, max_length=120)


class KeyRequest(BaseModel):
    key: str = Field(min_length=1, max_length=512)


class SettingsRequest(BaseModel):
    model_tier: str | None = Field(default=None, max_length=32)
    disclosure_accepted: bool | None = None
    history_enabled: bool | None = None


class AskRequest(BaseModel):
    question: str = Field(min_length=3, max_length=MAX_QUESTION_CHARS)
    book_ids: list[str] = Field(default_factory=list, max_length=64)
    campaign_id: str = Field(default="", max_length=64)


def _book_payload(book: Book) -> dict[str, Any]:
    payload = book.as_dict()
    # The stored path is an implementation detail; Godot shows the original name.
    payload.pop("stored_name", None)
    return payload


def _error(status_code: int, code: str, message: str) -> HTTPException:
    return HTTPException(status_code=status_code, detail={"code": code, "message": message})


def create_app(
    token: str,
    library: RulebookLibrary | None = None,
    assistant_factory: Callable[[Retriever, str], RulesAssistant] | None = None,
) -> FastAPI:
    if not token or len(token) < 16:
        raise ValueError("the helper requires a session token of at least 16 characters")

    paths.ensure_layout()
    books = library if library is not None else RulebookLibrary(ChunkIndex())
    retriever = Retriever(books.index, books)

    guard = threading.Lock()
    # One worker, so two imports queue instead of fighting over the library file.
    workers = ThreadPoolExecutor(max_workers=1, thread_name_prefix="redline-index")
    jobs: dict[str, Future] = {}

    @asynccontextmanager
    async def lifespan(_application: FastAPI) -> AsyncIterator[None]:
        yield
        workers.shutdown(wait=False, cancel_futures=True)

    application = FastAPI(
        title="Redline rulebook assistant",
        version=__version__,
        docs_url=None,
        redoc_url=None,
        lifespan=lifespan,
    )

    def authorize(supplied: str | None = Header(default=None, alias=TOKEN_HEADER)) -> None:
        if not supplied or not secrets.compare_digest(str(supplied), token):
            raise _error(401, "unauthorized", "This request did not carry Redline's session token.")

    authorized = [Depends(authorize)]

    def build_assistant() -> RulesAssistant:
        tier = str(settings.read()["model_tier"])
        if assistant_factory is not None:
            return assistant_factory(retriever, tier)
        try:
            key = credentials.load()
        except credentials.VaultUnavailable as exc:
            raise _error(503, "vault_unavailable", safe_error(exc)) from exc
        if not key:
            raise _error(400, "missing_key", "Add your Anthropic API key in Assistant Setup.")
        return RulesAssistant(retriever, key, tier)

    def start_indexing(book_id: str) -> None:
        running = jobs.get(book_id)
        if running is not None and not running.done():
            return

        def job() -> None:
            with guard:
                try:
                    books.index_book(book_id)
                except LibraryError:
                    # The failure is already recorded on the book, which the
                    # library listing reports; nothing is logged, because a log
                    # line is one more place book text could surface.
                    pass

        jobs[book_id] = workers.submit(job)

    @application.exception_handler(LibraryError)
    async def library_error(_request: Any, exception: LibraryError) -> JSONResponse:
        return JSONResponse(
            status_code=400, content={"detail": {"code": "library", "message": safe_error(exception)}}
        )

    @application.get("/health")
    def health() -> dict[str, Any]:
        return {"ok": True, "version": __version__, "name": "redline-assistant"}

    @application.get("/library", dependencies=authorized)
    def read_library() -> dict[str, Any]:
        with guard:
            listed = [_book_payload(book) for book in books.books()]
        return {
            "books": listed,
            "key": credentials.status().as_dict(),
            "settings": settings.read(),
            "model_tiers": sorted(MODELS),
        }

    @application.post("/library/import", dependencies=authorized)
    def import_book(request: ImportRequest) -> dict[str, Any]:
        with guard:
            book, created = books.import_pdf(request.path, request.label)
        if created or not book.searchable:
            start_indexing(book.book_id)
        return {"book": _book_payload(book), "imported": created}

    @application.post("/library/{book_id}/reindex", dependencies=authorized)
    def reindex_book(book_id: str) -> dict[str, Any]:
        with guard:
            book = books.book(book_id)
            if book is None:
                raise _error(404, "unknown_book", "That book is not in this installation's library.")
        start_indexing(book_id)
        return {"book": _book_payload(book)}

    @application.patch("/library/{book_id}", dependencies=authorized)
    def rename_book(book_id: str, request: LabelRequest) -> dict[str, Any]:
        with guard:
            return {"book": _book_payload(books.rename(book_id, request.label))}

    @application.delete("/library/{book_id}", dependencies=authorized)
    def remove_book(book_id: str) -> dict[str, Any]:
        with guard:
            books.remove(book_id)
        return {"removed": book_id}

    @application.get("/settings", dependencies=authorized)
    def read_settings() -> dict[str, Any]:
        return {"settings": settings.read(), "model_tiers": sorted(MODELS)}

    @application.put("/settings", dependencies=authorized)
    def write_settings(request: SettingsRequest) -> dict[str, Any]:
        if request.model_tier is not None and request.model_tier not in MODELS:
            raise _error(400, "unknown_tier", "Choose one of the offered model options.")
        return {"settings": settings.write(request.model_dump(exclude_none=True))}

    @application.get("/key", dependencies=authorized)
    def read_key() -> dict[str, Any]:
        return {"key": credentials.status().as_dict()}

    @application.put("/key", dependencies=authorized)
    def write_key(request: KeyRequest) -> dict[str, Any]:
        try:
            status = credentials.store(request.key)
        except ValueError as exc:
            raise _error(400, "invalid_key", str(exc)) from exc
        except credentials.VaultUnavailable as exc:
            raise _error(503, "vault_unavailable", safe_error(exc)) from exc
        return {"key": status.as_dict()}

    @application.delete("/key", dependencies=authorized)
    def delete_key() -> dict[str, Any]:
        try:
            credentials.remove()
        except credentials.VaultUnavailable as exc:
            raise _error(503, "vault_unavailable", safe_error(exc)) from exc
        return {"key": credentials.status().as_dict()}

    @application.post("/key/test", dependencies=authorized)
    def test_key() -> dict[str, Any]:
        assistant = build_assistant()
        try:
            assistant.verify_key()
        except AnswerError as exc:
            raise _error(400, exc.code, exc.message) from exc
        return {"ok": True, "model_tier": assistant.tier}

    @application.post("/ask", dependencies=authorized)
    def ask(request: AskRequest) -> dict[str, Any]:
        with guard:
            selection = books.resolve(request.book_ids)
        if not selection.books:
            waiting = [book.label for book in selection.not_ready]
            message = (
                "The active rulebooks are still being indexed."
                if waiting
                else "This campaign has no active rulebooks. Choose one in the Assistant tab."
            )
            raise _error(400, "no_active_books", message)
        assistant = build_assistant()
        try:
            answer = assistant.ask(request.question, selection.books)
        except AnswerError as exc:
            raise _error(400 if exc.code in {"missing_key", "invalid_key"} else 502, exc.code, exc.message) from exc
        payload = answer.as_dict()
        payload["unavailable_books"] = selection.missing
        payload["indexing_books"] = [book.label for book in selection.not_ready]
        payload["disclosure"] = prompts.DISCLOSURE
        if request.campaign_id and settings.read()["history_enabled"]:
            history.append(request.campaign_id, request.question, payload)
        return payload

    @application.get("/history/{campaign_id}", dependencies=authorized)
    def read_history(campaign_id: str) -> dict[str, Any]:
        return {"entries": history.read(campaign_id)}

    @application.delete("/history/{campaign_id}", dependencies=authorized)
    def clear_history(campaign_id: str) -> dict[str, Any]:
        history.clear(campaign_id)
        return {"entries": []}

    return application


__all__ = ["TOKEN_HEADER", "create_app"]
