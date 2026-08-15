"""Measure recall@3 and median latency against the real-question fixture."""

from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

from cprtool.index.query import RulesIndex


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, default=Path("data/rules.db"))
    parser.add_argument("--cases", type=Path, default=Path("tests/fixtures/retrieval_cases.json"))
    args = parser.parse_args(argv)
    cases = json.loads(args.cases.read_text(encoding="utf-8"))
    index = RulesIndex(args.database)
    successes = 0
    durations = []
    failures = []
    for case in cases:
        started = time.perf_counter()
        hits = index.search(case["question"], limit=3)
        durations.append((time.perf_counter() - started) * 1_000)
        pages = [hit.printed_page_start for hit in hits]
        if case["page"] in pages:
            successes += 1
        else:
            failures.append({"question": case["question"], "expected": case["page"], "returned": pages})
    recall = successes / len(cases)
    median_ms = statistics.median(durations)
    print(f"recall@3={recall:.3f} ({successes}/{len(cases)})")
    print(f"median_query_ms={median_ms:.2f}")
    for failure in failures:
        print(json.dumps(failure, ensure_ascii=False))
    return 0 if recall > 0.8 and median_ms < 300 else 1


if __name__ == "__main__":
    raise SystemExit(main())
