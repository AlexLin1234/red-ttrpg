"""Where the assistant keeps a Game Master's private library.

Everything here lives in the operating system's per-user application-data
directory, never in the repository, a campaign save, or an export staging
directory. ``REDLINE_ASSISTANT_HOME`` overrides the location, which is what the
tests use so a suite never touches a real installation.
"""

from __future__ import annotations

import os
from pathlib import Path

HOME_ENV = "REDLINE_ASSISTANT_HOME"


def application_home() -> Path:
    """The Redline application-data directory for the current user."""

    override = os.environ.get(HOME_ENV)
    if override:
        return Path(override).expanduser()
    if os.name == "nt":
        base = os.environ.get("APPDATA") or (Path.home() / "AppData" / "Roaming")
        return Path(base) / "Redline"
    if os.uname().sysname == "Darwin":
        return Path.home() / "Library" / "Application Support" / "Redline"
    base = os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share")
    return Path(base) / "Redline"


def assistant_home() -> Path:
    return application_home() / "assistant"


def books_dir() -> Path:
    return assistant_home() / "books"


def index_dir() -> Path:
    return assistant_home() / "index"


def history_dir() -> Path:
    return assistant_home() / "history"


def library_file() -> Path:
    return assistant_home() / "library.json"


def index_file() -> Path:
    return index_dir() / "chunks.sqlite3"


def settings_file() -> Path:
    """Non-secret helper settings. The API key never lands here."""

    return assistant_home() / "settings.json"


def ensure_layout() -> Path:
    """Create the private directory tree and return its root."""

    root = assistant_home()
    for directory in (root, books_dir(), index_dir(), history_dir()):
        directory.mkdir(parents=True, exist_ok=True)
    return root


__all__ = [
    "HOME_ENV",
    "application_home",
    "assistant_home",
    "books_dir",
    "ensure_layout",
    "history_dir",
    "index_dir",
    "index_file",
    "library_file",
    "settings_file",
]
