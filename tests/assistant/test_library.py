"""The global library: content hashing, duplicate detection, and book status."""

from __future__ import annotations

import threading

import pytest

from assistant import paths
from assistant.library import (
    STATUS_FAILED,
    STATUS_INDEXED,
    STATUS_INDEXING,
    STATUS_PENDING,
    STATUS_UNAVAILABLE,
    LibraryError,
    RulebookLibrary,
)

from conftest import ARMOR_RULE, CRITICAL_RULE


@pytest.fixture
def library():
    return RulebookLibrary()


def test_import_copies_the_pdf_into_private_application_data(library, make_pdf, tmp_path):
    source = make_pdf("Core Rules.pdf", [ARMOR_RULE, CRITICAL_RULE])

    book, created = library.import_pdf(source)

    assert created is True
    assert book.filename == "Core Rules.pdf"
    assert book.page_count == 2
    assert library.book_path(book).is_file()
    assert paths.books_dir() in library.book_path(book).parents
    # The original may now be moved or deleted without breaking the library.
    source.unlink()
    assert library.book_path(book).is_file()


def test_the_same_file_imported_twice_is_recognised_by_content_hash(library, make_pdf):
    first = make_pdf("Core Rules.pdf", [ARMOR_RULE])
    same_bytes_other_name = first.parent / "A Copy With Another Name.pdf"
    same_bytes_other_name.write_bytes(first.read_bytes())

    book, created = library.import_pdf(first)
    duplicate, created_again = library.import_pdf(same_bytes_other_name)

    assert created is True and created_again is False
    assert duplicate.book_id == book.book_id
    assert len(library.books()) == 1


def test_indexing_makes_a_book_searchable_and_survives_a_restart(library, make_pdf):
    book, _ = library.import_pdf(make_pdf("Core Rules.pdf", [ARMOR_RULE, CRITICAL_RULE]))
    assert book.status == STATUS_PENDING
    assert library.resolve([book.book_id]).books == []

    library.index_book(book.book_id)
    assert library.book(book.book_id).status == STATUS_INDEXED
    assert library.book(book.book_id).chunk_count == 2

    restarted = RulebookLibrary()
    assert [found.book_id for found in restarted.resolve([book.book_id]).books] == [book.book_id]


def test_a_scanned_pdf_is_refused_at_import(library, image_pdf):
    with pytest.raises(LibraryError, match="OCR"):
        library.import_pdf(image_pdf)

    assert library.books() == []


def test_a_book_whose_file_vanished_is_marked_unavailable_not_searchable(library, make_pdf):
    book, _ = library.import_pdf(make_pdf("Core Rules.pdf", [ARMOR_RULE]))
    library.index_book(book.book_id)

    library.book_path(book).unlink()
    restarted = RulebookLibrary()

    assert restarted.book(book.book_id).status == STATUS_UNAVAILABLE
    selection = restarted.resolve([book.book_id])
    assert selection.books == []
    assert [found.book_id for found in selection.not_ready] == [book.book_id]


def test_removing_a_book_leaves_a_campaign_that_referenced_it_intact(library, make_pdf):
    kept, _ = library.import_pdf(make_pdf("Core Rules.pdf", [ARMOR_RULE]))
    removed, _ = library.import_pdf(make_pdf("Black Chrome.pdf", [CRITICAL_RULE]))
    library.index_book(kept.book_id)
    library.index_book(removed.book_id)

    library.remove(removed.book_id)

    selection = RulebookLibrary().resolve([kept.book_id, removed.book_id])
    assert selection.book_ids == [kept.book_id]
    assert selection.missing == [removed.book_id]
    assert library.index.chunk_count(removed.book_id) == 0


def test_a_failed_index_is_reported_rather_than_claimed_as_success(library, make_pdf, monkeypatch):
    book, _ = library.import_pdf(make_pdf("Core Rules.pdf", [ARMOR_RULE]))

    def explode(*_args, **_kwargs):
        raise OSError("the disk went away")

    monkeypatch.setattr(library.index, "replace_book", explode)
    with pytest.raises(LibraryError):
        library.index_book(book.book_id)

    assert library.book(book.book_id).status == STATUS_FAILED
    assert library.resolve([book.book_id]).books == []


def test_renaming_changes_the_label_but_never_the_cited_filename(library, make_pdf):
    book, _ = library.import_pdf(make_pdf("Core Rules.pdf", [ARMOR_RULE]))

    renamed = library.rename(book.book_id, "  My table's core book  ")

    assert renamed.label == "My table's core book"
    assert renamed.filename == "Core Rules.pdf"


def test_the_library_stays_readable_while_a_book_is_being_indexed(library, make_pdf, monkeypatch):
    """Indexing must not lock out the tab that shows its progress.

    Godot gives every helper request a timeout and restarts the helper when one
    expires — which kills the index. So a listing taken during an index has to
    come back on its own, not queue behind the extraction.
    """

    book, _ = library.import_pdf(make_pdf("Core Rules.pdf", [ARMOR_RULE]))
    started = threading.Event()
    release = threading.Event()
    real_replace = library.index.replace_book

    def slow_replace(*args, **kwargs):
        started.set()
        assert release.wait(timeout=10), "the listing never came back"
        return real_replace(*args, **kwargs)

    monkeypatch.setattr(library.index, "replace_book", slow_replace)
    worker = threading.Thread(target=library.index_book, args=(book.book_id,))
    worker.start()
    try:
        assert started.wait(timeout=10), "indexing never began"
        # The listing is taken while the index thread is inside replace_book.
        listed = library.books()
        assert [entry.book_id for entry in listed] == [book.book_id]
        assert listed[0].status == STATUS_INDEXING
    finally:
        release.set()
        worker.join(timeout=10)

    assert not worker.is_alive()
    assert library.book(book.book_id).status == STATUS_INDEXED
