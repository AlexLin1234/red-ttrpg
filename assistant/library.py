"""The installation-wide rulebook library.

Books are global to one Redline installation; campaigns only remember which of
them are active. A book is identified by the SHA-256 of its bytes, so importing
the same file twice is recognised as the same book however it was named or
wherever it was found, and a campaign's stored ID keeps meaning the same book
across machines that hold the same file.

Imported PDFs are copied into private application data. The original in
Downloads can then be moved or deleted without breaking an index, and nothing
here ever writes into the repository, a campaign save, or an export.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import threading
from collections.abc import Callable
from dataclasses import asdict, dataclass, field, replace
from datetime import UTC, datetime
from pathlib import Path

from assistant import extract, paths
from assistant.extract import UnsupportedPDF
from assistant.index import ChunkIndex
from assistant.redaction import safe_error

LIBRARY_VERSION = 1
# Generous enough for an illustrated core rulebook, small enough that a stray
# file cannot fill the Game Master's disk before anything is validated.
MAX_PDF_BYTES = 512 * 1024 * 1024
MAX_LABEL_LENGTH = 120
BOOK_ID_LENGTH = 16

STATUS_PENDING = "pending"
STATUS_INDEXING = "indexing"
STATUS_INDEXED = "indexed"
STATUS_FAILED = "failed"
STATUS_UNAVAILABLE = "unavailable"


def _page_count_of(details: dict[str, object]) -> int:
    """Narrow the page count out of :func:`extract.inspect`'s open-typed result."""

    value = details.get("page_count", 0)
    return int(value) if isinstance(value, int) else 0


class LibraryError(RuntimeError):
    """A problem the Game Master can act on, phrased for the Library tab."""


@dataclass(slots=True)
class Book:
    book_id: str
    sha256: str
    filename: str
    label: str
    stored_name: str
    bytes: int
    page_count: int
    imported_at: str
    status: str = STATUS_PENDING
    indexed_at: str = ""
    chunk_count: int = 0
    indexed_pages: int = 0
    error: str = ""

    def as_dict(self) -> dict[str, object]:
        return asdict(self)

    @property
    def searchable(self) -> bool:
        return self.status == STATUS_INDEXED and self.chunk_count > 0


@dataclass(slots=True)
class ActiveSelection:
    """What a campaign's stored book IDs resolve to right now."""

    books: list[Book] = field(default_factory=list)
    missing: list[str] = field(default_factory=list)
    not_ready: list[Book] = field(default_factory=list)

    @property
    def book_ids(self) -> list[str]:
        return [book.book_id for book in self.books]


def _now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def file_digest(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def book_id_for(sha256: str) -> str:
    return sha256[:BOOK_ID_LENGTH]


class RulebookLibrary:
    def __init__(self, index: ChunkIndex | None = None) -> None:
        paths.ensure_layout()
        self.index = index if index is not None else ChunkIndex()
        self._books: dict[str, Book] = {}
        # Indexing runs on a worker thread while the API keeps answering, so the
        # book table and the file it is written to are guarded here. The lock is
        # only ever held for a dictionary update and a small write — never for
        # extraction, which is the slow part.
        self._lock = threading.RLock()
        self._load()

    # -- persistence --------------------------------------------------------

    def _load(self) -> None:
        location = paths.library_file()
        self._books = {}
        if location.is_file():
            try:
                document = json.loads(location.read_text(encoding="utf-8"))
                for row in document.get("books", []):
                    book = Book(**{key: row[key] for key in row if key in Book.__slots__})
                    self._books[book.book_id] = book
            except (OSError, TypeError, ValueError) as exc:
                raise LibraryError(f"The rulebook library file is unreadable: {safe_error(exc)}") from exc
        self._reconcile()

    def _reconcile(self) -> None:
        """Make the recorded status match what is actually on disk.

        A book whose PDF was deleted outside Redline is marked unavailable
        rather than quietly returned in searches, and a book the index no longer
        holds — because the index was rebuilt — goes back to pending so it can be
        re-indexed instead of answering nothing.
        """

        indexed = set(self.index.indexed_books())
        changed = False
        for book in self._books.values():
            present = self.book_path(book).is_file()
            if not present and book.status != STATUS_UNAVAILABLE:
                book.status = STATUS_UNAVAILABLE
                book.error = "The imported file is missing from Redline's library folder."
                changed = True
            elif present and book.status == STATUS_UNAVAILABLE:
                book.status = STATUS_INDEXED if book.book_id in indexed else STATUS_PENDING
                book.error = ""
                changed = True
            if book.status in (STATUS_INDEXED, STATUS_INDEXING) and book.book_id not in indexed:
                book.status = STATUS_PENDING
                book.chunk_count = 0
                book.indexed_pages = 0
                changed = True
            elif book.status == STATUS_INDEXED:
                count = self.index.chunk_count(book.book_id)
                if count != book.chunk_count:
                    book.chunk_count = count
                    changed = True
        if changed:
            self._save()

    def _save(self) -> None:
        location = paths.library_file()
        location.parent.mkdir(parents=True, exist_ok=True)
        with self._lock:
            document = {
                "version": LIBRARY_VERSION,
                "books": [book.as_dict() for book in self.books()],
            }
            temporary = location.with_suffix(".json.tmp")
            temporary.write_text(json.dumps(document, indent=2), encoding="utf-8")
            temporary.replace(location)

    # -- reading ------------------------------------------------------------

    def books(self) -> list[Book]:
        with self._lock:
            return sorted(self._books.values(), key=lambda book: book.label.lower())

    def book(self, book_id: str) -> Book | None:
        with self._lock:
            return self._books.get(book_id)

    def book_path(self, book: Book) -> Path:
        return paths.books_dir() / book.stored_name

    def resolve(self, book_ids: list[str]) -> ActiveSelection:
        """Split a campaign's stored IDs into searchable, missing and not-ready."""

        selection = ActiveSelection()
        with self._lock:
            for book_id in dict.fromkeys(book_ids):
                book = self._books.get(str(book_id))
                if book is None:
                    selection.missing.append(str(book_id))
                elif book.searchable:
                    selection.books.append(book)
                else:
                    selection.not_ready.append(book)
        return selection

    # -- importing ----------------------------------------------------------

    def import_pdf(self, source_path: str | Path, label: str = "") -> tuple[Book, bool]:
        """Copy a PDF into the library. Returns the book and whether it is new."""

        source = Path(source_path).expanduser()
        if not source.is_file():
            raise LibraryError("That file could not be found.")
        if source.suffix.lower() != ".pdf":
            raise LibraryError("Only PDF rulebooks can be imported.")
        size = source.stat().st_size
        if size <= 0:
            raise LibraryError("That file is empty.")
        if size > MAX_PDF_BYTES:
            raise LibraryError(f"That PDF is larger than the {MAX_PDF_BYTES // (1024 * 1024)} MB import limit.")
        try:
            details = extract.inspect(source)
        except UnsupportedPDF as exc:
            raise LibraryError(str(exc)) from exc

        sha256 = file_digest(source)
        book_id = book_id_for(sha256)
        with self._lock:
            existing = self._books.get(book_id)
        if existing is not None and self.book_path(existing).is_file():
            return existing, False

        stored_name = f"{book_id}.pdf"
        destination = paths.books_dir() / stored_name
        destination.parent.mkdir(parents=True, exist_ok=True)
        try:
            shutil.copyfile(source, destination)
        except OSError as exc:
            raise LibraryError(f"The book could not be copied into Redline: {safe_error(exc)}") from exc

        book = Book(
            book_id=book_id,
            sha256=sha256,
            filename=source.name,
            label=(label.strip() or source.name)[:MAX_LABEL_LENGTH],
            stored_name=stored_name,
            bytes=size,
            page_count=_page_count_of(details),
            imported_at=_now(),
            status=STATUS_PENDING,
        )
        if existing is not None:
            book = replace(book, label=existing.label, imported_at=existing.imported_at)
        with self._lock:
            self._books[book_id] = book
            self._save()
        return book, True

    def rename(self, book_id: str, label: str) -> Book:
        cleaned = label.strip()
        if not cleaned:
            raise LibraryError("Give the book a name.")
        with self._lock:
            book = self._require(book_id)
            book.label = cleaned[:MAX_LABEL_LENGTH]
            self._save()
        return book

    def remove(self, book_id: str) -> None:
        """Forget a book locally. Campaigns that reference it stay valid."""

        with self._lock:
            book = self._require(book_id)
            self.index.remove_book(book_id)
            stored = self.book_path(book)
            if stored.is_file():
                try:
                    stored.unlink()
                except OSError as exc:
                    raise LibraryError(f"The book file could not be deleted: {safe_error(exc)}") from exc
            del self._books[book_id]
            self._save()

    # -- indexing -----------------------------------------------------------

    def index_book(self, book_id: str, on_progress: Callable[[Book], None] | None = None) -> Book:
        """Extract and index one book, start to finish.

        A failure leaves the book marked failed with a readable reason; it never
        leaves a half-indexed book claiming to be searchable.

        Extraction runs outside the library lock. A core rulebook takes minutes,
        and holding the lock across it would stall every request Godot makes —
        including the /library poll whose timeout kills the helper mid-index.
        """

        with self._lock:
            book = self._require(book_id)
            source = self.book_path(book)
            if not source.is_file():
                book.status = STATUS_UNAVAILABLE
                book.error = "The imported file is missing from Redline's library folder."
                self._save()
                raise LibraryError(book.error)

            book.status = STATUS_INDEXING
            book.error = ""
            book.indexed_pages = 0
            book.chunk_count = 0
            self._save()
        if on_progress is not None:
            on_progress(book)

        def progress(page: int, chunks: int) -> None:
            book.indexed_pages = page
            book.chunk_count = chunks
            if on_progress is not None:
                on_progress(book)

        try:
            count = self.index.replace_book(book_id, extract.chunk_document(source, book_id), on_progress=progress)
        except UnsupportedPDF as exc:
            raise self._indexing_failed(book, str(exc)) from exc
        except Exception as exc:
            raise self._indexing_failed(book, f"Indexing failed: {safe_error(exc)}") from exc

        if count == 0:
            raise self._indexing_failed(book, "No searchable text was found in that PDF.")

        with self._lock:
            book.status = STATUS_INDEXED
            book.chunk_count = count
            book.indexed_pages = book.page_count
            book.indexed_at = _now()
            book.error = ""
            self._save()
        if on_progress is not None:
            on_progress(book)
        return book

    def _indexing_failed(self, book: Book, reason: str) -> LibraryError:
        """Roll one book back to a clean failed state and describe why."""

        with self._lock:
            self.index.remove_book(book.book_id)
            book.status = STATUS_FAILED
            book.error = reason
            book.chunk_count = 0
            self._save()
        return LibraryError(reason)

    def _require(self, book_id: str) -> Book:
        book = self._books.get(str(book_id))
        if book is None:
            raise LibraryError("That book is not in this Redline installation's library.")
        return book


__all__ = [
    "ActiveSelection",
    "Book",
    "LibraryError",
    "MAX_PDF_BYTES",
    "RulebookLibrary",
    "STATUS_FAILED",
    "STATUS_INDEXED",
    "STATUS_INDEXING",
    "STATUS_PENDING",
    "STATUS_UNAVAILABLE",
    "book_id_for",
    "file_digest",
]
