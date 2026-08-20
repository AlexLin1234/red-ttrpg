"""The audit that keeps books, indexes and keys out of a release."""

from __future__ import annotations

import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import audit_export  # noqa: E402


def test_the_repository_working_tree_is_clean():
    assert audit_export.audit(REPO_ROOT) == []


def test_a_staged_release_carrying_a_rulebook_fails(tmp_path):
    release = tmp_path / "Redline"
    (release / "assistant" / "books").mkdir(parents=True)
    (release / "assistant" / "books" / "abc123.pdf").write_bytes(b"%PDF-1.7 book bytes")

    problems = audit_export.audit(release)

    assert any("abc123.pdf" in problem for problem in problems)


def test_a_release_carrying_the_local_index_or_extracted_text_fails(tmp_path):
    release = tmp_path / "Redline"
    (release / "assistant" / "index").mkdir(parents=True)
    (release / "assistant" / "index" / "chunks.sqlite3").write_bytes(b"SQLite format 3\x00")
    (release / "assistant" / "chunks.jsonl").write_text('{"text": "a printed rule"}')
    (release / "assistant" / "library.json").write_text("{}")

    problems = "\n".join(audit_export.audit(release))

    assert "chunks.sqlite3" in problems
    assert "chunks.jsonl" in problems
    assert "library.json" in problems


def test_a_release_carrying_an_api_key_fails(tmp_path):
    release = tmp_path / "Redline"
    release.mkdir()
    (release / "config.json").write_text('{"anthropic_api_key": "sk-ant-api03-' + "q" * 40 + '"}')

    problems = audit_export.audit(release)

    assert any("API credential" in problem for problem in problems)


def test_a_packaged_archive_is_inspected_member_by_member(tmp_path):
    archive = tmp_path / "Redline.zip"
    with zipfile.ZipFile(archive, "w") as bundle:
        bundle.writestr("Redline/redline.exe", b"binary")
        bundle.writestr("Redline/assistant/books/abc123.pdf", b"%PDF-1.7")

    problems = audit_export.audit(archive)

    assert len(problems) == 1
    assert "abc123.pdf" in problems[0]


def test_a_clean_release_passes(tmp_path):
    release = tmp_path / "Redline"
    (release / "assistant").mkdir(parents=True)
    (release / "redline.exe").write_bytes(b"binary")
    (release / "assistant" / "service.py").write_text("# no secrets here\n")

    assert audit_export.audit(release) == []


def test_the_documentation_mockups_stay_shippable(tmp_path):
    package = tmp_path / "docs-only"
    (package / "docs" / "mockups").mkdir(parents=True)
    (package / "docs" / "mockups" / "1a-library.pdf").write_bytes(b"%PDF-1.7 mockup")

    assert audit_export.audit(package) == []
