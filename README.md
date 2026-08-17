# Cyberpunk RED Stream GM Tool

A local, single-GM tool for resolving combat, retrieving cited rules, and
presenting readable outcomes in an OBS-captured Godot scene.

Phases 0-8 are implemented: deterministic combat resolution, local validated
tables, reversible state, cited hybrid retrieval, the local GM HTTP service,
the OBS overlay, and an interactive Godot tactical viewer.

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

## Encounters and the viewer

The service also holds one live encounter. Every command resolves through the
pure resolver, is applied as reversible events, and is broadcast to attached
viewers as a full snapshot.

| Route                    | Purpose                                            |
| ------------------------ | -------------------------------------------------- |
| `POST /encounter`        | Load actors; clears undo history                   |
| `GET /encounter`         | Current snapshot                                   |
| `POST /encounter/attack` | Resolve one attack and broadcast the outcome card  |
| `POST /encounter/reload` | Refill a magazine                                  |
| `POST /encounter/clear-jam` | Clear a jammed weapon                           |
| `POST /encounter/month-end` | Close the month and auto-pay every Lifestyle    |
| `GET /map`               | Read the active map metadata and zones             |
| `PUT /map/image`         | Upload and normalize a GM-selected raster map      |
| `GET /map/image`         | Read the active map as a normalized PNG            |
| `PUT /map/zones`         | Replace the active map's normalized polygon zones  |
| `POST /encounter/undo`   | Reverse the last action                            |
| `POST /encounter/redo`   | Reapply the last undone action                     |
| `POST /resolve`          | Resolve an attack (tactical-viewer compatibility) |
| `WS /viewer`             | Snapshot stream for the Godot viewer               |

Attack commands may include `cover_hp`; the tactical viewer supplies this from
its shooter-to-target raycasts. The cover assignment and resulting damage are
recorded as one reversible event action.

An actor carries its own HP, armour SP, cover, cash, Lifestyle, and weapons.
The four Lifestyle costs and entitlements follow the sourcebook table on page
377. Closing a month bills the upcoming month as one reversible event action;
characters who cannot afford it are marked unpaid with a seven-day grace
period. Weapon stats come from the validated tables by name, or inline on the
actor when you want a one-off:

```json
{"current_month": "2045-01", "actors": {"solo": {
  "name": "Rache", "max_hp": 40, "attack_base": 14,
  "cash": 2400, "lifestyle": "good_prepak",
  "weapons": {"Heavy Pistol": {"ammo": 8}}
}}}
```

`POST /ask` with `"broadcast": true` also pushes the cited answer to the viewer.

Start the viewer once the service is running:

```powershell
godot --path viewer
python scripts\viewer_smoke.py
```

`viewer_smoke.py` drives a sample fight through the public routes so you can
confirm an OBS scene before going live. See `viewer/README.md` for the OBS
source settings and the layout map.

For the interactive isometric board, open
`viewer/new-game-project/project.godot` in Godot 4.7. It includes a 20×20
GridMap alley, three draggable billboard tokens, cover raycasts, the seven v1
actions, a compact inspector, resolution cards, combat VFX, and server-backed
undo/redo. Encounter snapshots dynamically create tokens and persist cover HP
by prop ID; Move mode also supports Shift-dragging cover props. The included
modular geometry and SVG portraits are original
placeholders that can be replaced with a licensed environment kit.

The tactical HUD lets the GM upload a PNG, JPEG, WebP, BMP, or TIFF as the
active map. Uploads are capped at 32 MB/40 megapixels, normalized to RGB PNG,
and stored with polygon zones under the ignored `data/maps/` directory. Press
**M** to show or hide the map, choose **Draw Zone**, left-click its vertices,
and right-click to finish. Zone coordinates are normalized, so they stay
aligned when the viewer changes size.

The sourcebook's Night City 2045 map remains an optional starting image. Keep
book content out of Git, extract it from a local PDF, and select the resulting
PNG through **Upload Map**:

```powershell
.\.venv\Scripts\python.exe scripts\extract_night_city_map.py `
  --pdf "C:\Users\skylo\Downloads\Books\Cyberpunk Red.pdf"
```
