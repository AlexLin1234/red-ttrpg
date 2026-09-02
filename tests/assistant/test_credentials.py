"""The key lives in the vault, and never appears in a message."""

from __future__ import annotations

import json

import pytest

from assistant import credentials, paths, redaction, settings

SAMPLE_KEY = "sk-ant-api03-" + "x" * 40


def test_a_stored_key_round_trips_through_the_vault(vault):
    status = credentials.store(SAMPLE_KEY)

    assert status.stored is True
    assert status.hint == "...xxxx"
    assert credentials.load() == SAMPLE_KEY
    assert credentials.status().stored is True

    credentials.remove()
    assert credentials.load() is None
    assert credentials.status().stored is False


def test_an_obviously_wrong_key_is_refused_before_any_request(vault):
    for candidate, complaint in (
        ("", "Paste an Anthropic"),
        ("hunter2", "does not look like"),
        ("api-key-" + "y" * 40, "starts with"),
        ("sk-ant-" + "y" * 20 + " trailing", "whitespace"),
    ):
        with pytest.raises(ValueError, match=complaint):
            credentials.validate(candidate)


def test_the_key_never_reaches_settings_or_any_file_on_disk(vault, private_home):
    credentials.store(SAMPLE_KEY)
    settings.write({"model_tier": "fast", "disclosure_accepted": True})

    stored = json.loads(paths.settings_file().read_text())
    assert SAMPLE_KEY not in json.dumps(stored)

    for path in private_home.rglob("*"):
        if path.is_file():
            assert SAMPLE_KEY not in path.read_bytes().decode("utf-8", "ignore")


def test_error_text_is_scrubbed_of_keys_and_authorization_headers(vault):
    credentials.store(SAMPLE_KEY)
    failure = RuntimeError(f"401 from api: x-api-key: {SAMPLE_KEY} (Authorization: Bearer {SAMPLE_KEY})")

    message = redaction.safe_error(failure)

    assert SAMPLE_KEY not in message
    assert "[redacted]" in message


def test_a_secret_is_forgotten_once_it_is_removed(vault):
    credentials.store(SAMPLE_KEY)
    credentials.remove()

    # Registered patterns still catch the shape even after the value is forgotten.
    assert SAMPLE_KEY not in redaction.redact(f"leaked {SAMPLE_KEY}")


def test_a_vault_that_panics_reads_as_no_key_rather_than_crashing(monkeypatch):
    """A broken native backend must degrade, not take the Assistant tab down.

    keyring sits on a stack of optional native libraries. A broken one does not
    always raise politely: the Rust-backed path raises
    ``pyo3_runtime.PanicException``, which inherits from ``BaseException`` and so
    walks straight through ``except Exception``. When that escaped, every request
    that drew the Assistant tab answered 500, because listing the library reports
    whether a key is stored.
    """

    class Panic(BaseException):
        """Stands in for pyo3_runtime.PanicException, which is not an Exception."""

    class PanickingVault:
        def get_password(self, service: str, account: str) -> str | None:
            raise Panic("Python API call failed")

        def set_password(self, service: str, account: str, password: str) -> None:
            raise Panic("Python API call failed")

        def delete_password(self, service: str, account: str) -> None:
            raise Panic("Python API call failed")

    monkeypatch.setattr(credentials, "_backend", lambda: PanickingVault())

    assert credentials.status() == credentials.KeyStatus(stored=False)
    assert credentials.remove() is False
    with pytest.raises(credentials.VaultUnavailable):
        credentials.load()
    with pytest.raises(credentials.VaultUnavailable):
        credentials.store(SAMPLE_KEY)


def test_an_interrupt_during_a_vault_call_is_not_swallowed(monkeypatch):
    """Widening the catch must not turn Ctrl-C into "no key stored"."""

    class InterruptingVault:
        def get_password(self, service: str, account: str) -> str | None:
            raise KeyboardInterrupt

    monkeypatch.setattr(credentials, "_backend", lambda: InterruptingVault())

    with pytest.raises(KeyboardInterrupt):
        credentials.status()
