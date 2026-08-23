"""The local SQLite chunk store: full-text index plus local vectors.

One database holds every imported book, and every query is filtered by the book
IDs the calling campaign has made active. A campaign can therefore never read a
passage — or a citation — out of a book it has not enabled, because rows from
inactive books are excluded inside SQL rather than filtered after the fact.
"""

from __future__ import annotations

import sqlite3
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

from assistant import paths
from assistant.embedding import DIMENSIONS, deserialize, embed, serialize, similarity
from assistant.extract import Chunk

SCHEMA_VERSION = 1

_SCHEMA = """
PRAGMA journal_mode = WAL;
CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS chunks (
    id INTEGER PRIMARY KEY,
    book_id TEXT NOT NULL,
    page INTEGER NOT NULL,
    ordinal INTEGER NOT NULL,
    text TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS chunks_by_book ON chunks(book_id);
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts
    USING fts5(text, content='chunks', content_rowid='id');
CREATE TABLE IF NOT EXISTS vectors (
    chunk_id INTEGER PRIMARY KEY REFERENCES chunks(id) ON DELETE CASCADE,
    book_id TEXT NOT NULL,
    embedding BLOB NOT NULL
);
CREATE INDEX IF NOT EXISTS vectors_by_book ON vectors(book_id);
"""


@dataclass(frozen=True, slots=True)
class Passage:
    """A retrieved chunk. [member page] is one-based, as printed in a viewer."""

    chunk_id: int
    book_id: str
    page: int
    text: str
    score: float


class ChunkIndex:
    def __init__(self, path: str | Path | None = None) -> None:
        self.path = Path(path) if path is not None else paths.index_file()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._prepare()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        return connection

    def _prepare(self) -> None:
        connection = self._connect()
        try:
            connection.executescript(_SCHEMA)
            self._reset_if_stale(connection)
            connection.execute(
                "INSERT OR REPLACE INTO metadata(key, value) VALUES ('schema_version', ?)",
                (str(SCHEMA_VERSION),),
            )
            connection.execute(
                "INSERT OR REPLACE INTO metadata(key, value) VALUES ('dimensions', ?)",
                (str(DIMENSIONS),),
            )
            connection.commit()
        finally:
            connection.close()

    @staticmethod
    def _reset_if_stale(connection: sqlite3.Connection) -> None:
        """Empty an index built by an older schema or a different vector size.

        The index is a cache of books the Game Master still owns, so throwing it
        away costs a re-index rather than any data. Leaving vectors of one length
        to be compared against queries of another would silently degrade every
        answer instead, which is far worse.
        """

        stored = {str(row["key"]): str(row["value"]) for row in connection.execute("SELECT key, value FROM metadata")}
        if not stored:
            return
        matches = stored.get("schema_version") == str(SCHEMA_VERSION) and stored.get("dimensions") == str(DIMENSIONS)
        if matches:
            return
        connection.execute("DELETE FROM chunks_fts")
        connection.execute("DELETE FROM vectors")
        connection.execute("DELETE FROM chunks")

    # -- writing ------------------------------------------------------------

    def replace_book(
        self,
        book_id: str,
        chunks: Iterable[Chunk],
        on_progress: Callable[[int, int], None] | None = None,
    ) -> int:
        """Index [param book_id] from scratch, returning the chunk count.

        Re-indexing replaces the book's rows in one transaction, so a failed or
        cancelled run can never leave half of a book searchable.
        """

        connection = self._connect()
        try:
            with connection:
                self._delete_book(connection, book_id)
                count = 0
                last_page = 0
                for chunk in chunks:
                    if chunk.book_id != book_id:
                        raise ValueError("chunk does not belong to the book being indexed")
                    cursor = connection.execute(
                        "INSERT INTO chunks(book_id, page, ordinal, text) VALUES (?, ?, ?, ?)",
                        (chunk.book_id, int(chunk.page), int(chunk.ordinal), chunk.text),
                    )
                    # sqlite3 types lastrowid as optional; an INSERT that ran
                    # without raising always has one.
                    chunk_id = int(cursor.lastrowid or 0)
                    connection.execute("INSERT INTO chunks_fts(rowid, text) VALUES (?, ?)", (chunk_id, chunk.text))
                    connection.execute(
                        "INSERT INTO vectors(chunk_id, book_id, embedding) VALUES (?, ?, ?)",
                        (chunk_id, chunk.book_id, serialize(embed(chunk.text))),
                    )
                    count += 1
                    if on_progress is not None and chunk.page != last_page:
                        last_page = chunk.page
                        on_progress(chunk.page, count)
            return count
        finally:
            connection.close()

    @staticmethod
    def _delete_book(connection: sqlite3.Connection, book_id: str) -> None:
        rows = connection.execute("SELECT id FROM chunks WHERE book_id = ?", (book_id,)).fetchall()
        for row in rows:
            connection.execute(
                "INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES ('delete', ?, (SELECT text FROM chunks WHERE id = ?))",
                (int(row["id"]), int(row["id"])),
            )
        connection.execute("DELETE FROM vectors WHERE book_id = ?", (book_id,))
        connection.execute("DELETE FROM chunks WHERE book_id = ?", (book_id,))

    def remove_book(self, book_id: str) -> None:
        connection = self._connect()
        try:
            with connection:
                self._delete_book(connection, book_id)
        finally:
            connection.close()

    # -- reading ------------------------------------------------------------

    def chunk_count(self, book_id: str | None = None) -> int:
        connection = self._connect()
        try:
            if book_id is None:
                row = connection.execute("SELECT count(*) AS total FROM chunks").fetchone()
            else:
                row = connection.execute(
                    "SELECT count(*) AS total FROM chunks WHERE book_id = ?", (book_id,)
                ).fetchone()
            return int(row["total"])
        finally:
            connection.close()

    def indexed_books(self) -> list[str]:
        connection = self._connect()
        try:
            return [
                str(row["book_id"])
                for row in connection.execute("SELECT DISTINCT book_id FROM chunks ORDER BY book_id")
            ]
        finally:
            connection.close()

    def search_text(self, expression: str, book_ids: Sequence[str], limit: int) -> list[Passage]:
        """Rank by BM25 over the full-text index, inside the active books only."""

        if not book_ids or not expression.strip() or limit < 1:
            return []
        placeholders = ",".join("?" for _ in book_ids)
        connection = self._connect()
        try:
            try:
                rows = connection.execute(
                    f"""
                    SELECT chunks.id, chunks.book_id, chunks.page, chunks.text,
                           bm25(chunks_fts) AS rank
                    FROM chunks_fts
                    JOIN chunks ON chunks.id = chunks_fts.rowid
                    WHERE chunks_fts MATCH ? AND chunks.book_id IN ({placeholders})
                    ORDER BY rank
                    LIMIT ?
                    """,
                    (expression, *book_ids, int(limit)),
                ).fetchall()
            except sqlite3.OperationalError:
                # A malformed MATCH expression is a bad question, not a crash.
                return []
        finally:
            connection.close()
        return [
            Passage(
                chunk_id=int(row["id"]),
                book_id=str(row["book_id"]),
                page=int(row["page"]),
                text=str(row["text"]),
                score=-float(row["rank"]),
            )
            for row in rows
        ]

    def search_vector(self, query: str, book_ids: Sequence[str], limit: int) -> list[Passage]:
        """Rank by cosine similarity against the local vectors.

        The scan is deliberately exhaustive over the active books: a personal
        library is thousands of chunks, not millions, and an exact scan removes a
        whole class of approximate-index bugs from a citation path.
        """

        if not book_ids or limit < 1:
            return []
        target = embed(query)
        placeholders = ",".join("?" for _ in book_ids)
        connection = self._connect()
        try:
            rows = connection.execute(
                f"""
                SELECT chunks.id, chunks.book_id, chunks.page, chunks.text, vectors.embedding
                FROM vectors
                JOIN chunks ON chunks.id = vectors.chunk_id
                WHERE vectors.book_id IN ({placeholders})
                """,
                tuple(book_ids),
            ).fetchall()
        finally:
            connection.close()
        scored = [
            Passage(
                chunk_id=int(row["id"]),
                book_id=str(row["book_id"]),
                page=int(row["page"]),
                text=str(row["text"]),
                score=similarity(target, deserialize(row["embedding"])),
            )
            for row in rows
        ]
        scored.sort(key=lambda passage: (-passage.score, passage.chunk_id))
        return [passage for passage in scored[:limit] if passage.score > 0.0]

    def passage(self, chunk_id: int) -> Passage | None:
        connection = self._connect()
        try:
            row = connection.execute(
                "SELECT id, book_id, page, text FROM chunks WHERE id = ?", (int(chunk_id),)
            ).fetchone()
        finally:
            connection.close()
        if row is None:
            return None
        return Passage(
            chunk_id=int(row["id"]),
            book_id=str(row["book_id"]),
            page=int(row["page"]),
            text=str(row["text"]),
            score=0.0,
        )


__all__ = ["ChunkIndex", "Passage", "SCHEMA_VERSION"]
