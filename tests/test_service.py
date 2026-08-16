from __future__ import annotations

import json
import asyncio
import threading
from pathlib import Path

import httpx
import pytest

from cprtool.gm.agent import AnthropicAgent, OfflineAgent
from cprtool.gm.prompts import SYSTEM_PROMPT
from cprtool.gm.service import create_app
from cprtool.gm.tools import GMTools
from cprtool.index.build_index import build_index
from cprtool.index.query import RulesIndex
from cprtool.rules.tables import JSONTables


def test_service_routes_are_grounded_and_advisory(tmp_path):
    chunks = tmp_path / "chunks.jsonl"
    chunks.write_text(json.dumps({
        "book": "Cyberpunk Red",
        "section": "Difficulty Values",
        "path": ["Getting It Done", "Difficulty Values"],
        "printed_page_start": 129,
        "printed_page_end": 129,
        "text": "Difficulty Values: Simple DV9, Everyday DV13, Difficult DV15, Professional DV17.",
    }) + "\n", encoding="utf-8")
    database = tmp_path / "rules.db"
    build_index(chunks, database)
    tables_path = tmp_path / "tables.json"
    tables_path.write_text(json.dumps({
        "ranged_dv": {}, "autofire_dv": {}, "weapons": {}, "armor": {},
        "critical_injuries": {}, "cover": {}, "aimed_shots": {}
    }), encoding="utf-8")
    tools = GMTools(RulesIndex(database), JSONTables(tables_path))
    app = create_app(agent=OfflineAgent(tools))

    async def exercise_routes():
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            assert (await client.get("/health")).json() == {"status": "ok"}
            answer = await client.post("/ask", json={"question": "What is an Everyday DV?"})
            assert answer.status_code == 200
            assert answer.json()["citations"][0]["page_start"] == 129

            arithmetic = await client.post("/ask", json={"question": "Calculate the total damage result for me"})
            assert arithmetic.status_code == 200
            assert "must come from the resolver" in arithmetic.json()["answer"]

            adjudication = await client.post("/adjudicate", json={"description": "A difficult rooftop jump"})
            assert adjudication.status_code == 200
            assert adjudication.json()["suggested_dv"] == 15
            assert adjudication.json()["requires_gm_approval"] is True

    asyncio.run(exercise_routes())


def test_arithmetic_is_reserved_for_resolver(tmp_path):
    assert "Never roll dice or perform damage" in SYSTEM_PROMPT


def test_ask_does_not_block_health_checks():
    entered = threading.Event()
    release = threading.Event()

    class BlockingAgent:
        def ask(self, question, book=None):
            entered.set()
            assert release.wait(timeout=2)
            return "Done", []

    app = create_app(agent=BlockingAgent())

    async def exercise_concurrency():
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            ask_task = asyncio.create_task(client.post("/ask", json={"question": "Wait here"}))
            assert await asyncio.to_thread(entered.wait, 1)
            health = await asyncio.wait_for(client.get("/health"), timeout=0.5)
            assert health.json() == {"status": "ok"}
            release.set()
            assert (await ask_task).status_code == 200

    try:
        asyncio.run(exercise_concurrency())
    finally:
        release.set()


def test_twenty_rules_questions_include_the_verified_page():
    root = Path(__file__).parents[1]
    database = root / "data" / "rules.db"
    tables_path = root / "cprtool" / "rules" / "tables.json"
    if not database.exists() or not tables_path.exists():
        pytest.skip("operator-local rules data is not built")
    agent = OfflineAgent(GMTools(RulesIndex(database), JSONTables(tables_path)))
    cases = json.loads((root / "tests" / "fixtures" / "retrieval_cases.json").read_text(encoding="utf-8"))[:20]
    for case in cases:
        answer, citations = agent.ask(case["question"])
        assert answer
        assert citations[0].page_start == case["page"]


def test_table_lookup_records_a_verifiable_citation():
    root = Path(__file__).parents[1]
    database = root / "data" / "rules.db"
    tables_path = root / "cprtool" / "rules" / "tables.json"
    if not database.exists() or not tables_path.exists():
        pytest.skip("operator-local rules data is not built")
    tools = GMTools(RulesIndex(database), JSONTables(tables_path))
    result = tools.lookup_table("armor", {"name": "Light Armorjack"})
    assert result["sp"] == 11
    assert result["citation"]["page_start"] == 185


def test_anthropic_agent_executes_only_registered_tool_calls():
    class Block:
        def __init__(self, payload):
            self.payload = payload

        def model_dump(self, mode="json"):
            return self.payload

    class Response:
        def __init__(self, *blocks):
            self.content = list(blocks)

    class Messages:
        def __init__(self):
            self.calls = []
            self.responses = iter((
                Response(Block({"type": "tool_use", "id": "tool-1", "name": "search_rules", "input": {"query": "armor"}})),
                Response(Block({"type": "text", "text": "Grounded answer (Cyberpunk Red, p. 186)"})),
            ))

        def create(self, **kwargs):
            self.calls.append(kwargs)
            return next(self.responses)

    class Client:
        def __init__(self):
            self.messages = Messages()

    class Tools:
        def __init__(self):
            self.citations = []
            self.dispatched = []

        def dispatch(self, name, arguments):
            self.dispatched.append((name, arguments))
            return {"results": []}

    agent = object.__new__(AnthropicAgent)
    agent.tools = Tools()
    agent.model = "test-model"
    agent.client = Client()
    answer, _ = agent.ask("When does armor ablate?")
    assert answer.startswith("Grounded answer")
    assert agent.tools.dispatched == [("search_rules", {"query": "armor"})]
    assert agent.client.messages.calls[0]["tools"]
