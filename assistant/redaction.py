"""Keep secrets and book text out of every string the console can see.

Two different things must never leave the helper as prose: the Game Master's
Anthropic API key, and the sourcebook passages the retriever loads. An error
message is the easiest place for either to escape, so every error the service
returns is passed through :func:`redact` first.
"""

from __future__ import annotations

import re

PLACEHOLDER = "[redacted]"

# Anthropic keys, and the generic long-token shapes an SDK or proxy may echo
# back inside an exception message.
_PATTERNS = (
    re.compile(r"sk-ant-[A-Za-z0-9_\-]{8,}"),
    re.compile(r"(?i)\b(api[_-]?key|authorization|x-api-key)\b\s*[:=]\s*\S+"),
    re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._\-]{8,}"),
)

_registered: set[str] = set()


def register_secret(secret: str) -> None:
    """Remember a live secret so it is scrubbed even in an unfamiliar shape."""

    if secret and len(secret) >= 8:
        _registered.add(secret)


def forget_secret(secret: str) -> None:
    _registered.discard(secret)


def redact(text: str) -> str:
    """Return [param text] with every known secret shape replaced."""

    cleaned = str(text)
    for secret in _registered:
        cleaned = cleaned.replace(secret, PLACEHOLDER)
    for pattern in _PATTERNS:
        cleaned = pattern.sub(PLACEHOLDER, cleaned)
    return cleaned


def safe_error(exception: BaseException, fallback: str = "the helper failed") -> str:
    """A one-line, secret-free description of a failure."""

    message = redact(str(exception)).strip()
    if not message:
        message = fallback
    return message if len(message) <= 400 else message[:397] + "..."


__all__ = ["PLACEHOLDER", "forget_secret", "redact", "register_secret", "safe_error"]
