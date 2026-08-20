"""Turn an imported PDF into page-cited chunks.

Every chunk carries the book it came from and the one-based PDF page it was read
from, because that pair is the whole citation the assistant is allowed to show.
Nothing downstream may invent either value, so nothing downstream is given the
chance: the page travels with the text from the moment it is extracted.
"""

from __future__ import annotations

import re
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

# A window is small enough that a citation points at something a GM can find on
# the page, and large enough to hold a complete printed rule.
MAX_CHUNK_CHARS = 1_400
MIN_CHUNK_CHARS = 200
OVERLAP_CHARS = 160

# A text-based rulebook yields text on nearly every page. A scan yields none, and
# is reported as unsupported rather than indexed into an empty index.
MIN_TEXT_PAGE_RATIO = 0.35
SAMPLE_PAGES = 40

_WHITESPACE = re.compile(r"[ \t\r\f\v]+")
_BLANK_LINES = re.compile(r"\n{3,}")


class UnsupportedPDF(ValueError):
    """The file cannot be indexed, and the Game Master needs to know why."""


@dataclass(frozen=True, slots=True)
class Chunk:
    """One retrievable passage, permanently attached to its source page."""

    book_id: str
    page: int
    ordinal: int
    text: str

    def as_dict(self) -> dict[str, object]:
        return {"book_id": self.book_id, "page": self.page, "ordinal": self.ordinal, "text": self.text}


def _document(path: str | Path):
    try:
        import pymupdf
    except ImportError as exc:  # pragma: no cover - depends on the install
        raise UnsupportedPDF("The PDF reader is unavailable in this installation.") from exc
    source = Path(path)
    if not source.is_file():
        raise UnsupportedPDF("That file no longer exists.")
    try:
        document = pymupdf.open(source)
    except Exception as exc:
        raise UnsupportedPDF("That file could not be opened as a PDF.") from exc
    if document.needs_pass:
        document.close()
        raise UnsupportedPDF("That PDF is password protected. Remove the password and import it again.")
    if document.page_count < 1:
        document.close()
        raise UnsupportedPDF("That PDF has no pages.")
    return document


def clean_text(text: str) -> str:
    """Normalize extractor whitespace without disturbing paragraph breaks."""

    collapsed = _WHITESPACE.sub(" ", text.replace("­", ""))
    lines = [line.strip() for line in collapsed.split("\n")]
    return _BLANK_LINES.sub("\n\n", "\n".join(lines)).strip()


def windows(text: str, max_chars: int = MAX_CHUNK_CHARS, overlap: int = OVERLAP_CHARS) -> list[str]:
    """Split one page into overlapping windows that end on word boundaries.

    The overlap exists so a rule that straddles a window boundary is still
    retrievable as a whole from one of the two windows.
    """

    body = " ".join(text.split())
    if not body:
        return []
    if max_chars < MIN_CHUNK_CHARS:
        raise ValueError("max_chars is too small to hold a printed rule")
    overlap = max(0, min(overlap, max_chars // 2))
    pieces: list[str] = []
    start = 0
    while start < len(body):
        end = start + max_chars
        if end >= len(body):
            pieces.append(body[start:].strip())
            break
        split = body.rfind(" ", start + max_chars // 2, end + 1)
        if split <= start:
            split = end
        pieces.append(body[start:split].strip())
        # Step back by the overlap, then forward to the next word boundary. The
        # window always advances, because `split` is strictly past `start`.
        resume = max(start + 1, split - overlap)
        space = body.find(" ", resume)
        start = space + 1 if space != -1 and space < split else split
    return [piece for piece in pieces if piece]


def page_texts(path: str | Path) -> Iterator[tuple[int, str]]:
    """Yield ``(one-based page number, cleaned text)`` for every page."""

    document = _document(path)
    try:
        for index in range(document.page_count):
            yield index + 1, clean_text(document[index].get_text("text"))
    finally:
        document.close()


def inspect(path: str | Path) -> dict[str, object]:
    """Page count and supportability, without indexing anything.

    Raises :class:`UnsupportedPDF` for an encrypted, empty, or image-only file so
    the import never reports success over a book that would answer nothing.
    """

    document = _document(path)
    try:
        page_count = int(document.page_count)
        step = max(1, page_count // SAMPLE_PAGES)
        sampled = 0
        with_text = 0
        for index in range(0, page_count, step):
            sampled += 1
            if len(clean_text(document[index].get_text("text"))) >= 40:
                with_text += 1
    finally:
        document.close()
    if sampled and with_text / sampled < MIN_TEXT_PAGE_RATIO:
        raise UnsupportedPDF(
            "That PDF holds page images rather than text, so it cannot be searched. "
            "Scanned books need OCR before Redline can index them."
        )
    return {"page_count": page_count, "text_pages_sampled": sampled, "text_pages_found": with_text}


def chunk_page(book_id: str, page: int, text: str, max_chars: int = MAX_CHUNK_CHARS) -> list[Chunk]:
    return [
        Chunk(book_id=book_id, page=page, ordinal=ordinal, text=window)
        for ordinal, window in enumerate(windows(clean_text(text), max_chars))
    ]


def chunk_document(path: str | Path, book_id: str, max_chars: int = MAX_CHUNK_CHARS) -> Iterator[Chunk]:
    for page, text in page_texts(path):
        yield from chunk_page(book_id, page, text, max_chars)


__all__ = [
    "Chunk",
    "MAX_CHUNK_CHARS",
    "UnsupportedPDF",
    "chunk_document",
    "chunk_page",
    "clean_text",
    "inspect",
    "page_texts",
    "windows",
]
