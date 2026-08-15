# Cyberpunk RED Stream GM Tool

A local, single-GM tool for resolving combat, retrieving cited rules, and
presenting readable outcomes in an OBS-captured Godot scene.

Phases 0-5 are implemented: deterministic combat resolution, local validated
tables, reversible state, cited hybrid retrieval, and the local GM HTTP service.

## Development

Python 3.11 or newer is required.

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -e ".[dev]"
pytest
```

Book-derived data is local-only. PDFs, extracted chunks, indexes, and the
operator's `cprtool/rules/tables.json` are ignored by Git.

To extract bookmark-aware chunks from a legally obtained rulebook:

```powershell
python -m cprtool.index.extract "C:\path\to\book.pdf" --output data\chunks.jsonl
```

Build the local rules index:

```powershell
python -m cprtool.index.build_index
python -m cprtool.index.query "When does armor ablate?"
python scripts\evaluate_retrieval.py
```

Extract table candidates and create side-by-side review previews:

```powershell
python -m cprtool.index.extract "C:\path\to\book.pdf" --tables --table-pages 173,183,185,187,188,341
python scripts\promote_table.py data\tables\page-173-table-1.csv --page-image data\tables\page-173.png --page 173 --key candidate_review.ranged_dv
```

Run the local GM service:

```powershell
python -m uvicorn cprtool.gm.service:app --host 127.0.0.1 --port 8000
```

`POST /ask` returns grounded rules answers and citations. `POST /adjudicate`
returns a suggested DV for explicit GM approval. Without an API key, the service
uses a deterministic extractive fallback. To enable the optional Anthropic agent,
set both `ANTHROPIC_API_KEY` and `CPR_ANTHROPIC_MODEL`; no model name is silently
selected for you.
