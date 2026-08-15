"""Extract bookmark-aware text chunks without putting book data in Git."""

from __future__ import annotations

import argparse
import csv
import json
from collections.abc import Iterable, Iterator
from dataclasses import asdict, dataclass
from pathlib import Path
import pymupdf
import pdfplumber


@dataclass(frozen=True, slots=True)
class Bookmark:
    level: int
    title: str
    page: int


@dataclass(frozen=True, slots=True)
class Chunk:
    book: str
    section: str
    path: tuple[str, ...]
    printed_page_start: int
    printed_page_end: int
    text: str


def _bookmarks(document: pymupdf.Document) -> list[Bookmark]:
    return [Bookmark(int(level), str(title), int(page)) for level, title, page, *_ in document.get_toc() if page > 0]


def _paths_by_page(page_count: int, bookmarks: Iterable[Bookmark]) -> list[tuple[str, ...]]:
    paths: list[tuple[str, ...]] = [()] * page_count
    stack: list[str] = []
    entries = sorted(bookmarks, key=lambda item: (item.page, item.level))
    cursor = 0
    for page_number in range(1, page_count + 1):
        while cursor < len(entries) and entries[cursor].page <= page_number:
            entry = entries[cursor]
            stack = stack[: max(0, entry.level - 1)]
            stack.append(entry.title)
            cursor += 1
        paths[page_number - 1] = tuple(stack)
    return paths


def _titles_by_page(page_count: int, bookmarks: Iterable[Bookmark]) -> list[tuple[str, ...]]:
    titles: list[list[str]] = [[] for _ in range(page_count)]
    for bookmark in bookmarks:
        page_index = bookmark.page - 1
        if 0 <= page_index < page_count:
            titles[page_index].append(bookmark.title)
    return [tuple(page_titles) for page_titles in titles]


def _visual_headings(page: pymupdf.Page) -> tuple[str, ...]:
    headings: list[str] = []
    for block in page.get_text("dict").get("blocks", []):
        for line in block.get("lines", []):
            spans = line.get("spans", [])
            text = " ".join("".join(span.get("text", "") for span in spans).split()).strip("▶◀ ")
            size = max((float(span.get("size", 0)) for span in spans), default=0)
            if size < 12 or not text or len(text.split()) > 16:
                continue
            if text.isdigit() or text.upper() in {"FRIDAY NIGHT FIREFIGHT", "GETTING IT DONE", "THE NEW STREET ECONOMY"}:
                continue
            if text not in headings:
                headings.append(text)
    return tuple(headings)


def _windows(text: str, limit: int) -> Iterator[str]:
    remaining = " ".join(text.split())
    while len(remaining) > limit:
        split = remaining.rfind(" ", 0, limit + 1)
        if split < limit // 2:
            split = limit
        yield remaining[:split].strip()
        remaining = remaining[split:].strip()
    if remaining:
        yield remaining


def extract_chunks(pdf_path: str | Path, max_chars: int = 6_000) -> Iterator[Chunk]:
    """Yield page-cited chunks. PDF index and printed folio are assumed equal."""

    source = Path(pdf_path)
    if max_chars < 500:
        raise ValueError("max_chars must be at least 500")
    with pymupdf.open(source) as document:
        bookmarks = _bookmarks(document)
        paths = _paths_by_page(document.page_count, bookmarks)
        titles = _titles_by_page(document.page_count, bookmarks)
        for page_index, page in enumerate(document):
            text = page.get_text("text")
            path = paths[page_index]
            labels = tuple(dict.fromkeys((*titles[page_index], *_visual_headings(page))))
            section = " | ".join(labels) or (path[-1] if path else f"Page {page_index}")
            for window in _windows(text, max_chars):
                yield Chunk(
                    book=source.stem,
                    section=section,
                    path=path,
                    printed_page_start=page_index,
                    printed_page_end=page_index,
                    text=window,
                )


def write_jsonl(chunks: Iterable[Chunk], output: str | Path) -> int:
    destination = Path(output)
    destination.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with destination.open("w", encoding="utf-8", newline="\n") as handle:
        for chunk in chunks:
            handle.write(json.dumps(asdict(chunk), ensure_ascii=False) + "\n")
            count += 1
    return count


def extract_tables(pdf_path: str | Path, output_dir: str | Path, pages: Iterable[int] | None = None) -> int:
    """Dump table candidates as CSV plus rasterized source pages."""

    destination = Path(output_dir)
    destination.mkdir(parents=True, exist_ok=True)
    page_filter = None if pages is None else set(pages)
    count = 0
    with pdfplumber.open(pdf_path) as pdf, pymupdf.open(pdf_path) as rendered:
        for page_index, page in enumerate(pdf.pages):
            if page_filter is not None and page_index not in page_filter:
                continue
            tables = page.extract_tables()
            if not tables:
                continue
            image_path = destination / f"page-{page_index}.png"
            rendered[page_index].get_pixmap(matrix=pymupdf.Matrix(1.5, 1.5), alpha=False).save(image_path)
            for table_index, table in enumerate(tables, 1):
                csv_path = destination / f"page-{page_index}-table-{table_index}.csv"
                width = max((len(row) for row in table if row), default=0)
                with csv_path.open("w", encoding="utf-8-sig", newline="") as handle:
                    writer = csv.writer(handle)
                    for row in table:
                        writer.writerow([(cell or "").strip() for cell in row] + [""] * (width - len(row)))
                count += 1
    return count


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path, help="path to a legally obtained rulebook PDF")
    parser.add_argument("--output", type=Path, default=Path("data/chunks.jsonl"))
    parser.add_argument("--max-chars", type=int, default=6_000)
    parser.add_argument("--tables", action="store_true", help="extract CSV table candidates instead of text chunks")
    parser.add_argument("--tables-output", type=Path, default=Path("data/tables"))
    parser.add_argument("--table-pages", help="comma-separated printed/PDF page indexes; default is every page")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.tables:
        pages = None if not args.table_pages else [int(value.strip()) for value in args.table_pages.split(",")]
        count = extract_tables(args.pdf, args.tables_output, pages)
        print(f"wrote {count} table candidates to {args.tables_output}")
        return 0
    count = write_jsonl(extract_chunks(args.pdf, args.max_chars), args.output)
    print(f"wrote {count} chunks to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
