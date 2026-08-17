from __future__ import annotations

import pytest

from cprtool.rules.lifestyle import LIFESTYLES, next_month, normalize_lifestyle


def test_sourcebook_lifestyle_costs_are_exact():
    assert {key: profile.monthly_cost for key, profile in LIFESTYLES.items()} == {
        "kibble": 100,
        "generic_prepak": 300,
        "good_prepak": 600,
        "fresh_food": 1_500,
    }
    assert all(profile.source_page == 377 for profile in LIFESTYLES.values())


def test_lifestyle_names_and_calendar_are_normalized():
    assert normalize_lifestyle("Good Prepak") == "good_prepak"
    assert normalize_lifestyle("fresh-food") == "fresh_food"
    assert next_month("2045-12") == "2046-01"
    with pytest.raises(ValueError, match="unknown Lifestyle"):
        normalize_lifestyle("Unlimited Caviar")
    with pytest.raises(ValueError, match="YYYY-MM"):
        next_month("January 2045")
