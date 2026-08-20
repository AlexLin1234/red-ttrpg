"""Retrieval never leaves the books a campaign has made active."""

from __future__ import annotations

import pytest

from assistant.library import RulebookLibrary
from assistant.retrieval import Retriever, query_terms

from conftest import ARMOR_RULE, CRITICAL_RULE, DLC_RULE


@pytest.fixture
def stocked(make_pdf):
    library = RulebookLibrary()
    core, _ = library.import_pdf(make_pdf("Core Rules.pdf", [ARMOR_RULE, CRITICAL_RULE]))
    dlc, _ = library.import_pdf(make_pdf("Black Chrome.pdf", [DLC_RULE]))
    library.index_book(core.book_id)
    library.index_book(dlc.book_id)
    return library, library.book(core.book_id), library.book(dlc.book_id)


def test_a_question_finds_the_passage_that_answers_it(stocked):
    library, core, _dlc = stocked

    hits = Retriever(library.index, library).search("when does armor ablate?", [core])

    assert hits, "the armor rule should be retrievable"
    assert hits[0].citation.page == 1
    assert hits[0].citation.filename == "Core Rules.pdf"
    assert "ablates" in hits[0].passage.text


def test_an_inactive_book_is_never_retrieved_or_cited(stocked):
    library, core, dlc = stocked
    retriever = Retriever(library.index, library)

    core_only = retriever.search("how much does a shield ablate", [core])
    both = retriever.search("how much does a shield ablate", [core, dlc])

    assert all(hit.citation.book_id == core.book_id for hit in core_only)
    assert dlc.book_id in {hit.citation.book_id for hit in both}


def test_no_active_book_means_no_passages(stocked):
    library, _core, _dlc = stocked

    assert Retriever(library.index, library).search("armor ablation", []) == []


def test_every_passage_is_tagged_with_a_unique_marker(stocked):
    library, core, dlc = stocked

    hits = Retriever(library.index, library).search("armor ablation shield", [core, dlc])

    markers = [hit.marker for hit in hits]
    assert markers == sorted(set(markers), key=markers.index)
    assert markers[0] == "c1"


def test_query_terms_drop_table_language_and_de_inflect():
    assert query_terms("How does armor ablation work when I'm shot?") == [
        "armor",
        "ablation",
        "work",
        "shot",
    ]
    assert query_terms("what is the ???") == []
