"""Fail a release that carries private material.

Redline ships no sourcebook content, no extracted text, no index, and no
credentials. Those all live in a Game Master's own application data, and the
only reliable way to keep them there is to check every package before it goes
out — and the working tree, so nothing private is committed in the first place.

    python scripts/audit_export.py                 # the repository working tree
    python scripts/audit_export.py build/Redline   # a staged release directory
    python scripts/audit_export.py dist/Redline.zip
"""

from __future__ import annotations

import argparse
import re
import zipfile
from collections.abc import Iterator
from pathlib import Path

# Book-derived and private-by-nature files, by name.
FORBIDDEN_NAMES = {
    "chunks.jsonl",
    "rules.db",
    "library.json",
    "items_local.json",
    "settings.json.tmp",
}
FORBIDDEN_SUFFIXES = {".pdf", ".red", ".sqlite3", ".sqlite", ".db-wal", ".db-shm"}
FORBIDDEN_DIRECTORY_PARTS = {"books", "chunks", "tables"}

# Documentation mockups are the one place a committed PDF is legitimate.
ALLOWED_PREFIXES = ("docs/mockups/",)

# Anything holding a credential, wherever it hides.
SECRET_PATTERNS = (
    re.compile(rb"sk-ant-[A-Za-z0-9_\-]{8,}"),
    re.compile(rb"(?i)anthropic[_-]?api[_-]?key\s*[:=]\s*[\"']?[A-Za-z0-9_\-]{12,}"),
)
SCANNABLE_SUFFIXES = {
    ".cfg",
    ".gd",
    ".godot",
    ".ini",
    ".json",
    ".md",
    ".py",
    ".sh",
    ".toml",
    ".tres",
    ".tscn",
    ".txt",
    ".yaml",
    ".yml",
}
MAX_SCAN_BYTES = 2 * 1024 * 1024

SKIP_DIRECTORIES = {".git", ".godot", "__pycache__", ".shots", "node_modules", ".venv"}


def _is_allowed(relative: str) -> bool:
    return any(relative.startswith(prefix) for prefix in ALLOWED_PREFIXES)


def check_name(relative: str) -> str | None:
    """Why this path may not ship, or ``None`` when it may."""

    if _is_allowed(relative):
        return None
    path = Path(relative)
    if path.name in FORBIDDEN_NAMES:
        return "book-derived or private data file"
    if path.suffix.lower() in FORBIDDEN_SUFFIXES:
        return f"private {path.suffix.lower()} file"
    parts = set(path.parts)
    if "assistant" in parts and parts & FORBIDDEN_DIRECTORY_PARTS:
        return "imported rulebook or extracted text"
    if "index" in parts and path.suffix.lower() in {".sqlite3", ".db"}:
        return "local search index"
    return None


def _walk(root: Path) -> Iterator[tuple[str, Path]]:
    for path in sorted(root.rglob("*")):
        if path.is_dir() or SKIP_DIRECTORIES & set(path.parts):
            continue
        yield path.relative_to(root).as_posix(), path


def _credential_in(data: bytes) -> str | None:
    for pattern in SECRET_PATTERNS:
        if pattern.search(data):
            return "an API credential"
    return None


def audit_directory(root: Path) -> list[str]:
    problems: list[str] = []
    for relative, path in _walk(root):
        reason = check_name(relative)
        if reason is not None:
            problems.append(f"{relative}: {reason}")
            continue
        if path.suffix.lower() in SCANNABLE_SUFFIXES and path.stat().st_size <= MAX_SCAN_BYTES:
            secret = _credential_in(path.read_bytes())
            if secret is not None:
                problems.append(f"{relative}: contains {secret}")
    return problems


def audit_archive(archive: Path) -> list[str]:
    problems: list[str] = []
    with zipfile.ZipFile(archive) as bundle:
        for info in bundle.infolist():
            if info.is_dir():
                continue
            reason = check_name(info.filename)
            if reason is not None:
                problems.append(f"{archive.name}!{info.filename}: {reason}")
                continue
            if Path(info.filename).suffix.lower() in SCANNABLE_SUFFIXES and info.file_size <= MAX_SCAN_BYTES:
                secret = _credential_in(bundle.read(info))
                if secret is not None:
                    problems.append(f"{archive.name}!{info.filename}: contains {secret}")
    return problems


def audit(target: str | Path) -> list[str]:
    path = Path(target)
    if not path.exists():
        return [f"{path}: nothing to audit at this path"]
    if path.is_file() and zipfile.is_zipfile(path):
        return audit_archive(path)
    if path.is_file():
        reason = check_name(path.name)
        return [f"{path.name}: {reason}"] if reason else []
    return audit_directory(path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "targets",
        nargs="*",
        default=[str(Path(__file__).resolve().parent.parent)],
        help="directories or archives to audit; defaults to the repository",
    )
    args = parser.parse_args(argv)

    failures: list[str] = []
    for target in args.targets:
        failures.extend(audit(target))
    if failures:
        print("Private material must not ship:")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print(f"Clean: {', '.join(str(target) for target in args.targets)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
