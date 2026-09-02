"""The Anthropic API key lives in the operating-system credential vault.

Redline never embeds a developer key, never proxies Game Masters through a
shared key, and never writes their key to a settings file, a campaign save, a
log line, or a process argument. The only thing stored outside the vault is the
fact that a key exists, which the Assistant Setup tab needs in order to draw its
status.
"""

from __future__ import annotations

from dataclasses import dataclass

from assistant import redaction

SERVICE_NAME = "Redline Assistant"
ACCOUNT_NAME = "anthropic-api-key"

# Anthropic keys start with this prefix; catching an obvious paste error here
# saves a round trip and a confusing authentication failure.
KEY_PREFIX = "sk-ant-"
MIN_KEY_LENGTH = 24
MAX_KEY_LENGTH = 512


class VaultUnavailable(RuntimeError):
    """Raised when the platform has no usable credential vault."""


@dataclass(frozen=True, slots=True)
class KeyStatus:
    stored: bool
    hint: str = ""

    def as_dict(self) -> dict[str, object]:
        return {"stored": self.stored, "hint": self.hint}


def _backend():
    try:
        import keyring
    except ImportError as exc:  # pragma: no cover - depends on the install
        raise VaultUnavailable(
            "The operating-system credential vault is unavailable, so the API key cannot be stored securely."
        ) from exc
    return keyring


# Control flow, not vault failure: these must reach the caller untouched.
_PASS_THROUGH = (KeyboardInterrupt, SystemExit, GeneratorExit, MemoryError)


def _vault(operation: str, call, *args):
    """Run one vault call, turning any backend failure into ``VaultUnavailable``.

    Catching ``BaseException`` rather than ``Exception`` is deliberate. A keyring
    backend is a stack of optional native libraries, and a broken one does not
    always fail politely: a Rust backend raises ``pyo3_runtime.PanicException``,
    which inherits straight from ``BaseException``, so an ``except Exception``
    here lets it past and turns a missing key into a 500 on every request that
    draws the Assistant tab. A vault this module cannot read is the same
    condition however it failed — the key is unavailable, and the caller is
    expected to carry on without one.
    """

    try:
        return call(*args)
    except VaultUnavailable:
        raise
    except _PASS_THROUGH:
        raise
    except BaseException as exc:
        raise VaultUnavailable(redaction.safe_error(exc, operation)) from exc


def validate(key: str) -> str:
    """Return the trimmed key, or raise ``ValueError`` describing the problem."""

    candidate = (key or "").strip()
    if not candidate:
        raise ValueError("Paste an Anthropic API key.")
    if len(candidate) < MIN_KEY_LENGTH or len(candidate) > MAX_KEY_LENGTH:
        raise ValueError("That does not look like an Anthropic API key.")
    if not candidate.startswith(KEY_PREFIX):
        raise ValueError("An Anthropic API key starts with 'sk-ant-'.")
    if any(character.isspace() for character in candidate):
        raise ValueError("The key contains whitespace; copy it again.")
    return candidate


def hint_for(key: str) -> str:
    """The last four characters, which is all the setup tab ever displays."""

    return f"...{key[-4:]}" if len(key) >= 4 else ""


def store(key: str) -> KeyStatus:
    candidate = validate(key)
    _vault(
        "the credential vault refused the key",
        _backend().set_password,
        SERVICE_NAME,
        ACCOUNT_NAME,
        candidate,
    )
    redaction.register_secret(candidate)
    return KeyStatus(stored=True, hint=hint_for(candidate))


def load() -> str | None:
    """The stored key, or ``None``. Callers must never log the result."""

    key = _vault(
        "the credential vault could not be read",
        _backend().get_password,
        SERVICE_NAME,
        ACCOUNT_NAME,
    )
    if key:
        redaction.register_secret(key)
    return key


def remove() -> bool:
    key = None
    try:
        key = load()
    except VaultUnavailable:
        pass
    try:
        _vault(
            "the credential vault could not be written",
            _backend().delete_password,
            SERVICE_NAME,
            ACCOUNT_NAME,
        )
    except VaultUnavailable:
        # Deleting a key that was never stored is not a failure worth surfacing.
        return False
    if key:
        redaction.forget_secret(key)
    return True


def status() -> KeyStatus:
    try:
        key = load()
    except VaultUnavailable:
        return KeyStatus(stored=False)
    if not key:
        return KeyStatus(stored=False)
    return KeyStatus(stored=True, hint=hint_for(key))


__all__ = [
    "ACCOUNT_NAME",
    "KEY_PREFIX",
    "KeyStatus",
    "SERVICE_NAME",
    "VaultUnavailable",
    "hint_for",
    "load",
    "remove",
    "status",
    "store",
    "validate",
]
