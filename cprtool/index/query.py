"""Fast cited hybrid retrieval over the local rulebook index."""

from __future__ import annotations

import argparse
import json
import sqlite3
from dataclasses import asdict, dataclass
from pathlib import Path

import sqlite_vec

from cprtool.index.embedding import embed, serialize, tokens


STOPWORDS = {
    "a", "an", "and", "are", "at", "be", "can", "do", "does", "for", "how",
    "i", "in", "is", "it", "many", "my", "of", "on", "or", "the", "to",
    "what", "when", "where", "which", "with", "work",
}
GENERIC_QUERY_WORDS = {
    "cause", "difference", "give", "given", "have", "interact", "penalty",
    "consume", "provide", "rolled", "stats", "take", "use", "used", "using",
    "character", "meter", "meters",
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
}

@dataclass(frozen=True, slots=True)
class SearchHit:
    chunk_id: int
    book: str
    section: str
    path: str
    printed_page_start: int
    printed_page_end: int
    text: str
    score: float

    @property
    def citation(self) -> str:
        if self.printed_page_start == self.printed_page_end:
            return f"{self.book}, p. {self.printed_page_start}"
        return f"{self.book}, pp. {self.printed_page_start}-{self.printed_page_end}"


class RulesIndex:
    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)
        if not self.path.exists():
            raise FileNotFoundError(f"rules index not found: {self.path}")

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path)
        connection.row_factory = sqlite3.Row
        connection.enable_load_extension(True)
        sqlite_vec.load(connection)
        connection.enable_load_extension(False)
        return connection

    @staticmethod
    def _query_tokens(query: str) -> list[str]:
        raw_tokens = [token for token in tokens(query) if token not in STOPWORDS and token not in GENERIC_QUERY_WORDS]
        expanded = []
        for token in raw_tokens:
            if token.endswith("ing") and len(token) > 6:
                token = token[:-3]
            elif token.endswith("ed") and len(token) > 5:
                token = token[:-2]
            elif token.endswith("ies") and len(token) > 4:
                token = token[:-3] + "y"
            elif token.endswith("s") and len(token) > 4:
                token = token[:-1]
            expanded.append(token)
        query_tokens = list(dict.fromkeys(expanded))
        if "melee" in query_tokens and "armor" in query_tokens:
            query_tokens.append("combat")
        if not query_tokens:
            raise ValueError("query must contain searchable text")
        return query_tokens

    @classmethod
    def _fts_expression(cls, query: str) -> str:
        query_tokens = cls._query_tokens(query)
        return " OR ".join(f'"{token}"' for token in query_tokens)

    @classmethod
    def _strict_expression(cls, connection: sqlite3.Connection, query: str) -> str | None:
        candidates: list[tuple[int, str]] = []
        for token in cls._query_tokens(query):
            term = f"{token}*" if len(token) >= 5 else f'"{token}"'
            frequency = int(connection.execute(
                "SELECT count(*) FROM chunks_fts WHERE chunks_fts MATCH ?", (term,)
            ).fetchone()[0])
            if frequency:
                candidates.append((frequency, term))
        if not candidates:
            return None
        anchors = [term for _, term in sorted(candidates)[:4]]
        return " AND ".join(anchors)

    def search(self, query: str, book: str | None = None, limit: int = 6) -> list[SearchHit]:
        if limit < 1:
            raise ValueError("limit must be positive")
        connection = self._connect()
        try:
            strict_expression = self._strict_expression(connection, query)
            strict_rows = [] if strict_expression is None else connection.execute(
                """
                SELECT rowid AS id
                FROM chunks_fts
                WHERE chunks_fts MATCH ?
                ORDER BY bm25(chunks_fts, 1.0, 4.0, 3.0)
                LIMIT 20
                """,
                (strict_expression,),
            ).fetchall()
            fts_rows = connection.execute(
                """
                SELECT rowid AS id
                FROM chunks_fts
                WHERE chunks_fts MATCH ?
                ORDER BY bm25(chunks_fts, 1.0, 4.0, 3.0)
                LIMIT 20
                """,
                (self._fts_expression(query),),
            ).fetchall()
            vec_rows = connection.execute(
                """
                SELECT rowid AS id, distance
                FROM chunks_vec
                WHERE embedding MATCH ? AND k = 20
                ORDER BY distance
                """,
                (serialize(embed(query)),),
            ).fetchall()
            scores: dict[int, float] = {}
            for rank, row in enumerate(strict_rows, 1):
                scores[int(row["id"])] = scores.get(int(row["id"]), 0.0) + 10.0 / (60 + rank)
            for rank, row in enumerate(fts_rows, 1):
                scores[int(row["id"])] = scores.get(int(row["id"]), 0.0) + 3.0 / (60 + rank)
            for rank, row in enumerate(vec_rows, 1):
                scores[int(row["id"])] = scores.get(int(row["id"]), 0.0) + 0.5 / (60 + rank)
            ranked_ids = sorted(scores, key=lambda rowid: (-scores[rowid], rowid))
            hits: list[SearchHit] = []
            for rowid in ranked_ids:
                row = connection.execute("SELECT * FROM chunks WHERE id = ?", (rowid,)).fetchone()
                if row is None or (book and str(row["book"]).lower() != book.lower()):
                    continue
                hits.append(
                    SearchHit(
                        chunk_id=rowid,
                        book=str(row["book"]),
                        section=str(row["section"]),
                        path=str(row["path"]),
                        printed_page_start=int(row["printed_page_start"]),
                        printed_page_end=int(row["printed_page_end"]),
                        text=str(row["text"]),
                        score=scores[rowid],
                    )
                )
                if len(hits) >= limit:
                    break
            return hits
        finally:
            connection.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("query")
    parser.add_argument("--database", type=Path, default=Path("data/rules.db"))
    parser.add_argument("--book")
    parser.add_argument("--limit", type=int, default=6)
    args = parser.parse_args(argv)
    hits = RulesIndex(args.database).search(args.query, args.book, args.limit)
    for hit in hits:
        print(json.dumps(asdict(hit), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
