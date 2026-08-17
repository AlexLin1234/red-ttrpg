"""Small deterministic embeddings for offline hybrid retrieval."""

from __future__ import annotations

import hashlib
import math
import re
from array import array
from collections import Counter


DIMENSIONS = 256
TOKEN_RE = re.compile(r"[a-z0-9]+")


def tokens(text: str) -> list[str]:
    return TOKEN_RE.findall(text.lower())


def embed(text: str, dimensions: int = DIMENSIONS) -> list[float]:
    """Return a normalized signed feature-hashing vector."""

    words = tokens(text)
    features = words + [f"{left}_{right}" for left, right in zip(words, words[1:])]
    counts = Counter(features)
    vector = [0.0] * dimensions
    for feature, count in counts.items():
        digest = hashlib.blake2s(feature.encode("utf-8"), digest_size=8).digest()
        bucket = int.from_bytes(digest[:4], "little") % dimensions
        sign = 1.0 if digest[4] & 1 else -1.0
        vector[bucket] += sign * (1.0 + math.log(count))
    magnitude = math.sqrt(sum(value * value for value in vector))
    if magnitude:
        vector = [value / magnitude for value in vector]
    return vector


def serialize(vector: list[float]) -> bytes:
    return array("f", vector).tobytes()


__all__ = ["DIMENSIONS", "embed", "serialize", "tokens"]
