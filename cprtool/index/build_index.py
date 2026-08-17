"""Build the local FTS5 + sqlite-vec rules index."""

from __future__ import annotations

import argparse
import json
import sqlite3
from collections.abc import Iterable
from pathlib import Path
from typing import Any

import sqlite_vec

from cprtool.index.embedding import DIMENSIONS, embed, serialize


SCHEMA_VERSION = "1"


def _connect(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(path)
    connection.enable_load_extension(True)
    sqlite_vec.load(connection)
    connection.enable_load_extension(False)
    return connection


def _read_chunks(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"invalid JSON on {path}:{line_number}") from exc


def build_index(chunks_path: str | Path, database_path: str | Path) -> int:
    source = Path(chunks_path)
    destination = Path(database_path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        destination.unlink()
    connection = _connect(destination)
    try:
        connection.executescript(
            f"""
            PRAGMA journal_mode = DELETE;
            PRAGMA synchronous = NORMAL;
            CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE chunks (
                id INTEGER PRIMARY KEY,
                book TEXT NOT NULL,
                section TEXT NOT NULL,
                path TEXT NOT NULL,
                printed_page_start INTEGER NOT NULL,
                printed_page_end INTEGER NOT NULL,
                text TEXT NOT NULL
            );
            CREATE VIRTUAL TABLE chunks_fts USING fts5(text, section, path);
            CREATE VIRTUAL TABLE chunks_vec USING vec0(embedding float[{DIMENSIONS}]);
            """
        )
        connection.execute("INSERT INTO metadata VALUES ('schema_version', ?)", (SCHEMA_VERSION,))
        count = 0
        for count, chunk in enumerate(_read_chunks(source), 1):
            path_text = " > ".join(chunk.get("path", []))
            cursor = connection.execute(
                """
                INSERT INTO chunks(book, section, path, printed_page_start, printed_page_end, text)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    chunk["book"],
                    chunk["section"],
                    path_text,
                    int(chunk["printed_page_start"]),
                    int(chunk["printed_page_end"]),
                    chunk["text"],
                ),
            )
            rowid = int(cursor.lastrowid)
            connection.execute(
                "INSERT INTO chunks_fts(rowid, text, section, path) VALUES (?, ?, ?, ?)",
                (rowid, chunk["text"], chunk["section"], path_text),
            )
            embedding_text = f"{chunk['section']} {path_text} {chunk['section']} {chunk['text']}"
            connection.execute(
                "INSERT INTO chunks_vec(rowid, embedding) VALUES (?, ?)",
                (rowid, serialize(embed(embedding_text))),
            )
        connection.execute("INSERT INTO metadata VALUES ('chunk_count', ?)", (str(count),))
        connection.commit()
        return count
    finally:
        connection.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chunks", type=Path, default=Path("data/chunks.jsonl"))
    parser.add_argument("--database", type=Path, default=Path("data/rules.db"))
    args = parser.parse_args(argv)
    count = build_index(args.chunks, args.database)
    print(f"indexed {count} chunks into {args.database}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
