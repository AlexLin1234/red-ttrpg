"""Hybrid retrieval over the campaign's active books.

Two rankers disagree usefully: BM25 finds the printed wording a Game Master half
remembers, and the local vectors find the passage when they ask in table
language instead. Their rankings are fused, and every surviving passage carries
the book and page it came from so a citation can be checked against it later.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import TYPE_CHECKING

from assistant.embedding import tokens
from assistant.index import ChunkIndex, Passage

if TYPE_CHECKING:  # pragma: no cover - typing only
    from assistant.library import Book, RulebookLibrary

MAX_QUESTION_CHARS = 600
MAX_PASSAGES = 8
MAX_PASSAGE_CHARS = 1_600
CANDIDATES_PER_RANKER = 20

# Reciprocal-rank fusion, weighted so an exact-phrase hit outranks a merely
# similar one without letting either ranker win alone.
WEIGHT_STRICT = 10.0
WEIGHT_ANY = 3.0
WEIGHT_VECTOR = 2.0
RRF_K = 60

STOPWORDS = frozenset(
    """a an and are as at be but by can do does for from has have how i if in is it its many
    me my no not of on or should that the their them then there these this to use using was
    what when where which who why will with would you your""".split()
)
_WORD = re.compile(r"[a-z0-9]+")


def query_terms(question: str) -> list[str]:
    """Content words, lightly de-inflected so 'ablates' finds 'ablate'."""

    terms: list[str] = []
    for token in tokens(question):
        if token in STOPWORDS or len(token) < 2:
            continue
        if token.endswith("ies") and len(token) > 4:
            token = token[:-3] + "y"
        elif token.endswith("ing") and len(token) > 6:
            token = token[:-3]
        elif token.endswith("ed") and len(token) > 5:
            token = token[:-2]
        elif token.endswith("es") and len(token) > 4:
            token = token[:-2]
        elif token.endswith("s") and len(token) > 3:
            token = token[:-1]
        terms.append(token)
    return list(dict.fromkeys(terms))


def any_expression(terms: list[str]) -> str:
    """Match a passage holding any query term; prefixes catch inflections."""

    return " OR ".join(f'"{term}"*' for term in terms)


def strict_expression(terms: list[str]) -> str:
    """Match a passage holding every distinctive term at once."""

    distinctive = [term for term in terms if len(term) >= 4] or terms
    return " AND ".join(f'"{term}"*' for term in distinctive[:5])


@dataclass(frozen=True, slots=True)
class Citation:
    """The only provenance the assistant is ever allowed to show."""

    book_id: str
    filename: str
    page: int

    @property
    def label(self) -> str:
        return f"{self.filename} — PDF page {self.page}"

    def as_dict(self) -> dict[str, object]:
        return {
            "book_id": self.book_id,
            "filename": self.filename,
            "page": self.page,
            "label": self.label,
        }


@dataclass(frozen=True, slots=True)
class RetrievedPassage:
    """A passage handed to the model, tagged with the marker it must cite by."""

    marker: str
    passage: Passage
    citation: Citation

    @property
    def text(self) -> str:
        body = self.passage.text
        return body if len(body) <= MAX_PASSAGE_CHARS else body[:MAX_PASSAGE_CHARS] + "..."


def _fuse(ranked: list[tuple[float, list[Passage]]]) -> list[Passage]:
    scores: dict[int, float] = {}
    best: dict[int, Passage] = {}
    for weight, passages in ranked:
        for rank, passage in enumerate(passages, start=1):
            scores[passage.chunk_id] = scores.get(passage.chunk_id, 0.0) + weight / (RRF_K + rank)
            best.setdefault(passage.chunk_id, passage)
    order = sorted(scores, key=lambda chunk_id: (-scores[chunk_id], chunk_id))
    return [
        Passage(
            chunk_id=chunk_id,
            book_id=best[chunk_id].book_id,
            page=best[chunk_id].page,
            text=best[chunk_id].text,
            score=scores[chunk_id],
        )
        for chunk_id in order
    ]


class Retriever:
    """Searches only the books a campaign has made active."""

    def __init__(self, index: ChunkIndex, library: "RulebookLibrary") -> None:
        self.index = index
        self.library = library

    def search(self, question: str, books: list["Book"], limit: int = MAX_PASSAGES) -> list[RetrievedPassage]:
        query = (question or "").strip()[:MAX_QUESTION_CHARS]
        book_ids = [book.book_id for book in books]
        terms = query_terms(query)
        if not query or not book_ids or not terms:
            return []
        limit = max(1, min(limit, MAX_PASSAGES))
        filenames = {book.book_id: book.filename for book in books}
        fused = _fuse(
            [
                (
                    WEIGHT_STRICT,
                    self.index.search_text(strict_expression(terms), book_ids, CANDIDATES_PER_RANKER),
                ),
                (
                    WEIGHT_ANY,
                    self.index.search_text(any_expression(terms), book_ids, CANDIDATES_PER_RANKER),
                ),
                (WEIGHT_VECTOR, self.index.search_vector(query, book_ids, CANDIDATES_PER_RANKER)),
            ]
        )
        results: list[RetrievedPassage] = []
        for position, passage in enumerate(fused[:limit], start=1):
            results.append(
                RetrievedPassage(
                    marker=f"c{position}",
                    passage=passage,
                    citation=Citation(
                        book_id=passage.book_id,
                        filename=filenames.get(passage.book_id, passage.book_id),
                        page=passage.page,
                    ),
                )
            )
        return results


__all__ = [
    "CANDIDATES_PER_RANKER",
    "Citation",
    "MAX_PASSAGES",
    "MAX_PASSAGE_CHARS",
    "MAX_QUESTION_CHARS",
    "RetrievedPassage",
    "Retriever",
    "any_expression",
    "query_terms",
    "strict_expression",
]
