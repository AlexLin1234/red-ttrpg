from __future__ import annotations

import json
import statistics
import time
from pathlib import Path

import pytest

from cprtool.index.query import RulesIndex


ROOT = Path(__file__).parents[1]
DATABASE = ROOT / "data" / "rules.db"
CASES = json.loads((ROOT / "tests" / "fixtures" / "retrieval_cases.json").read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def index():
    if not DATABASE.exists():
        pytest.skip("operator-local data/rules.db has not been built")
    return RulesIndex(DATABASE)


def test_retrieval_recall_at_three(index):
    successes = 0
    failures = []
    for case in CASES:
        pages = [hit.printed_page_start for hit in index.search(case["question"], limit=3)]
        if case["page"] in pages:
            successes += 1
        else:
            failures.append((case["question"], case["page"], pages))
    recall = successes / len(CASES)
    assert recall > 0.8, f"recall@3={recall:.3f}; failures={failures}"


def test_median_query_under_300ms(index):
    durations = []
    for case in CASES:
        started = time.perf_counter()
        index.search(case["question"], limit=6)
        durations.append((time.perf_counter() - started) * 1_000)
    assert statistics.median(durations) < 300
