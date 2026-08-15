"""Review an extracted CSV beside its source page and promote it to tables.json."""

from __future__ import annotations

import argparse
import csv
import html
import json
import webbrowser
from pathlib import Path
from typing import Any


def _csv_rows(path: Path) -> list[list[str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return [row for row in csv.reader(handle)]


def _preview(csv_path: Path, page_image: Path, rows: list[list[str]]) -> Path:
    preview = csv_path.with_suffix(".preview.html")
    table = "".join("<tr>" + "".join(f"<td>{html.escape(cell)}</td>" for cell in row) + "</tr>" for row in rows)
    document = f"""<!doctype html><meta charset="utf-8"><title>Table promotion review</title>
<style>body{{font:14px system-ui;margin:20px;background:#181818;color:#eee}}main{{display:grid;grid-template-columns:1fr 1fr;gap:20px}}img{{width:100%;height:auto}}table{{border-collapse:collapse;width:100%}}td{{border:1px solid #777;padding:6px;vertical-align:top}}</style>
<h1>{html.escape(csv_path.name)}</h1><main><img src="{page_image.as_uri()}"><table>{table}</table></main>"""
    preview.write_text(document, encoding="utf-8")
    return preview


def _set_nested(document: dict[str, Any], key: str, value: Any) -> None:
    parts = key.split(".")
    current = document
    for part in parts[:-1]:
        current = current.setdefault(part, {})
        if not isinstance(current, dict):
            raise ValueError(f"key crosses a non-object at {part}")
    current[parts[-1]] = value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path)
    parser.add_argument("--page-image", type=Path, required=True)
    parser.add_argument("--key", required=True, help="dot-separated destination key")
    parser.add_argument("--tables", type=Path, default=Path("cprtool/rules/tables.json"))
    parser.add_argument("--value-file", type=Path, help="validated JSON value; defaults to CSV rows")
    parser.add_argument("--page", type=int, required=True)
    parser.add_argument("--open", action="store_true", help="open the generated side-by-side HTML preview")
    parser.add_argument("--yes", action="store_true", help="promote without an interactive confirmation")
    args = parser.parse_args(argv)

    rows = _csv_rows(args.csv)
    preview = _preview(args.csv.resolve(), args.page_image.resolve(), rows)
    print(f"Review preview: {preview.resolve()}")
    if args.open:
        webbrowser.open(preview.resolve().as_uri())
    if not args.yes and input("Promote this validated table? [y/N] ").strip().lower() != "y":
        print("not promoted")
        return 1
    if args.value_file:
        value = json.loads(args.value_file.read_text(encoding="utf-8"))
    else:
        value = {"page": args.page, "rows": rows}
    document = json.loads(args.tables.read_text(encoding="utf-8")) if args.tables.exists() else {}
    _set_nested(document, args.key, value)
    args.tables.parent.mkdir(parents=True, exist_ok=True)
    args.tables.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"promoted {args.key} to {args.tables}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
