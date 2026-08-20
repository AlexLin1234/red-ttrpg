"""Extraction keeps the page a passage came from attached to its text."""

from __future__ import annotations

import pytest

from assistant import extract
from assistant.extract import UnsupportedPDF

from conftest import ARMOR_RULE, CRITICAL_RULE


def test_every_chunk_carries_its_one_based_pdf_page(make_pdf):
    pdf = make_pdf("rules.pdf", [ARMOR_RULE, CRITICAL_RULE])
    chunks = list(extract.chunk_document(pdf, "book1"))

    assert [chunk.page for chunk in chunks] == [1, 2]
    assert all(chunk.book_id == "book1" for chunk in chunks)
    assert "ablates" in chunks[0].text
    assert "explodes" in chunks[1].text


def test_a_long_page_splits_into_overlapping_windows_on_one_page(make_pdf):
    body = " ".join(f"rule{number}" for number in range(400))
    chunks = extract.chunk_page("book1", 7, body, max_chars=400)

    assert len(chunks) > 1
    assert {chunk.page for chunk in chunks} == {7}
    assert [chunk.ordinal for chunk in chunks] == list(range(len(chunks)))
    assert all(len(chunk.text) <= 400 for chunk in chunks)
    # Nothing is lost at a window boundary.
    joined = " ".join(chunk.text for chunk in chunks)
    assert "rule0" in joined and "rule399" in joined


def test_inspect_reports_the_page_count(make_pdf):
    details = extract.inspect(make_pdf("rules.pdf", [ARMOR_RULE] * 5))

    assert details["page_count"] == 5


def test_an_encrypted_pdf_is_rejected_with_a_readable_reason(make_pdf):
    protected = make_pdf("locked.pdf", [ARMOR_RULE], encrypt="chrome")

    with pytest.raises(UnsupportedPDF, match="password"):
        extract.inspect(protected)


def test_a_scanned_pdf_is_reported_unsupported_rather_than_half_indexed(image_pdf):
    with pytest.raises(UnsupportedPDF, match="OCR"):
        extract.inspect(image_pdf)


def test_a_file_that_is_not_a_pdf_is_rejected(tmp_path):
    decoy = tmp_path / "notes.pdf"
    decoy.write_text("this is not a PDF at all")

    with pytest.raises(UnsupportedPDF):
        extract.inspect(decoy)
