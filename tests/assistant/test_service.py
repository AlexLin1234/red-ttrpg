"""The loopback contract Godot depends on, including who is allowed to call it."""

from __future__ import annotations

import threading

import pytest
from fastapi.testclient import TestClient

from assistant import history, prompts
from assistant.agent import RulesAssistant
from assistant.library import RulebookLibrary
from assistant.retrieval import Retriever
from assistant.service import TOKEN_HEADER, create_app

from conftest import ARMOR_RULE, CRITICAL_RULE, DLC_RULE
from test_agent import FakeClient, search_then

TOKEN = "session-token-for-tests-0123456789"
SAMPLE_KEY = "sk-ant-api03-" + "z" * 40


@pytest.fixture
def stocked(make_pdf):
    library = RulebookLibrary()
    core, _ = library.import_pdf(make_pdf("Core Rules.pdf", [ARMOR_RULE, CRITICAL_RULE]))
    dlc, _ = library.import_pdf(make_pdf("Black Chrome.pdf", [DLC_RULE]))
    library.index_book(core.book_id)
    library.index_book(dlc.book_id)
    return library


@pytest.fixture
def answering(stocked):
    """A client whose assistant always answers with one validated citation."""

    def factory(retriever: Retriever, tier: str) -> RulesAssistant:
        client = FakeClient(search_then("Armor ablates one point [c1]."))
        return RulesAssistant(retriever, "sk-ant-test", tier, client=client)

    app = create_app(TOKEN, library=stocked, assistant_factory=factory)
    with TestClient(app) as client:
        client.headers.update({TOKEN_HEADER: TOKEN})
        yield client, stocked


def test_the_helper_refuses_a_request_without_the_session_token(stocked):
    app = create_app(TOKEN, library=stocked)
    with TestClient(app) as client:
        assert client.get("/health").status_code == 200

        for response in (
            client.get("/library"),
            client.get("/library", headers={TOKEN_HEADER: "wrong-token-entirely-0000"}),
            client.post("/ask", json={"question": "when does armor ablate"}),
        ):
            assert response.status_code == 401
            assert response.json()["detail"]["code"] == "unauthorized"


def test_a_token_short_enough_to_guess_is_refused_at_startup(stocked):
    with pytest.raises(ValueError):
        create_app("short", library=stocked)


def test_the_library_listing_names_files_without_exposing_stored_paths(answering):
    client, library = answering

    payload = client.get("/library").json()

    assert {book["filename"] for book in payload["books"]} == {"Core Rules.pdf", "Black Chrome.pdf"}
    assert all("stored_name" not in book for book in payload["books"])
    assert all(book["status"] == "indexed" and book["chunk_count"] > 0 for book in payload["books"])
    assert payload["key"] == {"stored": False, "hint": ""}
    assert payload["model_tiers"] == ["capable", "fast"]


def test_importing_the_same_pdf_twice_is_reported_as_a_duplicate(stocked, make_pdf):
    app = create_app(TOKEN, library=stocked)
    with TestClient(app) as client:
        client.headers.update({TOKEN_HEADER: TOKEN})
        source = make_pdf("Interface RED.pdf", [ARMOR_RULE])

        first = client.post("/library/import", json={"path": str(source)}).json()
        second = client.post("/library/import", json={"path": str(source)}).json()

        assert first["imported"] is True and second["imported"] is False
        assert first["book"]["book_id"] == second["book"]["book_id"]


def test_an_unsupported_pdf_import_explains_itself(stocked, image_pdf):
    app = create_app(TOKEN, library=stocked)
    with TestClient(app) as client:
        client.headers.update({TOKEN_HEADER: TOKEN})

        response = client.post("/library/import", json={"path": str(image_pdf)})

        assert response.status_code == 400
        assert "OCR" in response.json()["detail"]["message"]


def test_an_answer_carries_validated_citations_and_the_transmission_notice(answering):
    client, library = answering
    core = next(book for book in library.books() if book.filename == "Core Rules.pdf")

    payload = client.post(
        "/ask",
        json={"question": "When does armor ablate?", "book_ids": [core.book_id], "campaign_id": "camp1"},
    ).json()

    assert payload["status"] == "answered"
    assert payload["citations"][0]["filename"] == "Core Rules.pdf"
    assert payload["citations"][0]["page"] == 1
    assert payload["citations"][0]["label"].endswith("PDF page 1")
    assert payload["disclosure"] == prompts.DISCLOSURE
    assert payload["unavailable_books"] == []


def test_a_book_that_is_not_active_is_never_cited_for_that_campaign(answering):
    client, library = answering
    core = next(book for book in library.books() if book.filename == "Core Rules.pdf")
    dlc = next(book for book in library.books() if book.filename == "Black Chrome.pdf")

    payload = client.post("/ask", json={"question": "armor ablation", "book_ids": [core.book_id]}).json()

    assert {citation["book_id"] for citation in payload["citations"]} == {core.book_id}
    assert dlc.book_id not in {citation["book_id"] for citation in payload["citations"]}


def test_a_removed_book_is_reported_as_unavailable_instead_of_failing_the_campaign(answering):
    client, library = answering
    core = next(book for book in library.books() if book.filename == "Core Rules.pdf")

    payload = client.post(
        "/ask", json={"question": "armor ablation", "book_ids": [core.book_id, "deadbeefdeadbeef"]}
    ).json()

    assert payload["status"] == "answered"
    assert payload["unavailable_books"] == ["deadbeefdeadbeef"]


def test_asking_with_no_active_books_routes_the_gm_back_to_the_choice(answering):
    client, _library = answering

    response = client.post("/ask", json={"question": "armor ablation", "book_ids": []})

    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "no_active_books"


def test_history_is_kept_per_campaign_and_can_be_cleared(answering):
    client, library = answering
    core = next(book for book in library.books() if book.filename == "Core Rules.pdf")
    body = {"question": "When does armor ablate?", "book_ids": [core.book_id], "campaign_id": "camp1"}

    client.post("/ask", json=body)
    entries = client.get("/history/camp1").json()["entries"]

    assert len(entries) == 1
    assert entries[0]["question"] == body["question"]
    assert entries[0]["citations"][0]["page"] == 1

    assert client.delete("/history/camp1").json()["entries"] == []
    assert history.read("camp1") == []


def test_the_key_is_accepted_replaced_and_removed_through_the_vault(stocked, vault):
    app = create_app(TOKEN, library=stocked)
    with TestClient(app) as client:
        client.headers.update({TOKEN_HEADER: TOKEN})

        assert client.get("/key").json()["key"]["stored"] is False
        stored = client.put("/key", json={"key": SAMPLE_KEY}).json()["key"]
        assert stored == {"stored": True, "hint": "...zzzz"}

        rejected = client.put("/key", json={"key": "definitely-not-a-key"})
        assert rejected.status_code == 400
        assert rejected.json()["detail"]["code"] == "invalid_key"
        assert SAMPLE_KEY not in rejected.text

        assert client.delete("/key").json()["key"]["stored"] is False


def test_settings_keep_the_model_choice_out_of_campaign_data(stocked):
    app = create_app(TOKEN, library=stocked)
    with TestClient(app) as client:
        client.headers.update({TOKEN_HEADER: TOKEN})

        assert client.get("/settings").json()["settings"]["model_tier"] == "capable"
        updated = client.put("/settings", json={"model_tier": "fast", "disclosure_accepted": True})
        assert updated.json()["settings"] == {
            "model_tier": "fast",
            "disclosure_accepted": True,
            "history_enabled": True,
        }

        rejected = client.put("/settings", json={"model_tier": "claude-something-else"})
        assert rejected.status_code == 400
        assert rejected.json()["detail"]["code"] == "unknown_tier"


def test_a_question_longer_than_the_limit_is_rejected_before_any_request(answering):
    client, library = answering
    core = next(book for book in library.books() if book.filename == "Core Rules.pdf")

    response = client.post(
        "/ask", json={"question": "a" * 5_000, "book_ids": [core.book_id]}
    )

    assert response.status_code == 422


def test_the_library_answers_while_a_book_is_being_indexed(make_pdf, monkeypatch):
    """The indexing worker must not hold the lock the request handlers take.

    Godot times a request out after two minutes and restarts the helper when one
    expires, which kills the running index. A tab left open on a large import
    could therefore never finish it: the listing queued behind the extraction,
    timed out, and took the extraction down with it.
    """

    library = RulebookLibrary()
    started, release = threading.Event(), threading.Event()

    def slow_index(book_id, on_progress=None):
        started.set()
        assert release.wait(timeout=10), "the listing never came back"
        return library.book(book_id)

    monkeypatch.setattr(library, "index_book", slow_index)
    app = create_app(TOKEN, library=library)
    with TestClient(app) as client:
        client.headers.update({TOKEN_HEADER: TOKEN})
        imported = client.post(
            "/library/import", json={"path": str(make_pdf("Core Rules.pdf", [ARMOR_RULE]))}
        )
        assert imported.status_code == 200, imported.text
        assert started.wait(timeout=10), "indexing never began"

        # Read the listing off another thread, so a handler that blocks fails
        # the test instead of hanging the suite. The answer has to arrive while
        # the index is still held open — releasing first would let a serialized
        # listing through and prove nothing.
        answered = {}
        replied = threading.Event()

        def read_listing() -> None:
            answered["response"] = client.get("/library")
            replied.set()

        reader = threading.Thread(target=read_listing)
        reader.start()
        try:
            in_time = replied.wait(timeout=10)
        finally:
            release.set()
        reader.join(timeout=10)

    assert in_time, "/library did not answer while a book was being indexed"
    assert answered["response"].status_code == 200
    assert [book["filename"] for book in answered["response"].json()["books"]] == [
        "Core Rules.pdf"
    ]
