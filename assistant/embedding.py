"""Deterministic local embeddings.

Semantic-ish recall without a second cloud account: a feature-hashing sketch
over words and word pairs, computed on the Game Master's own machine. It costs
nothing, needs no model download, and — being deterministic — an index built on
one Redline installation scores identically on another.

Weights are non-negative on purpose. Signed feature hashing keeps collisions
unbiased, but at these dimensions two features can cancel a shared word to
exactly zero, which reads as "unrelated" for a query that plainly overlaps the
passage. Unsigned buckets can only ever add a little collision noise instead.
"""

from __future__ import annotations

import hashlib
import math
import re
from array import array
from collections import Counter

DIMENSIONS = 512
# A word pair is corroborating evidence, not a word in its own right.
BIGRAM_WEIGHT = 0.5
TOKEN_RE = re.compile(r"[a-z0-9]+")


def tokens(text: str) -> list[str]:
    return TOKEN_RE.findall(text.lower())


def _bucket(feature: str, dimensions: int) -> int:
    digest = hashlib.blake2s(feature.encode("utf-8"), digest_size=8).digest()
    return int.from_bytes(digest[:4], "little") % dimensions


def embed(text: str, dimensions: int = DIMENSIONS) -> list[float]:
    """Return a unit-length, non-negative feature-hashing vector."""

    words = tokens(text)
    vector = [0.0] * dimensions
    for feature, count in Counter(words).items():
        vector[_bucket(feature, dimensions)] += 1.0 + math.log(count)
    for feature, count in Counter(f"{a}_{b}" for a, b in zip(words, words[1:])).items():
        vector[_bucket(feature, dimensions)] += BIGRAM_WEIGHT * (1.0 + math.log(count))
    magnitude = math.sqrt(sum(value * value for value in vector))
    if magnitude:
        vector = [value / magnitude for value in vector]
    return vector


def serialize(vector: list[float]) -> bytes:
    return array("f", vector).tobytes()


def deserialize(blob: bytes) -> list[float]:
    values = array("f")
    values.frombytes(blob)
    return list(values)


def similarity(left: list[float], right: list[float]) -> float:
    """Cosine similarity. Both sides are already unit length."""

    return sum(a * b for a, b in zip(left, right))


__all__ = [
    "BIGRAM_WEIGHT",
    "DIMENSIONS",
    "deserialize",
    "embed",
    "serialize",
    "similarity",
    "tokens",
]
