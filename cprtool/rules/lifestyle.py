"""Cyberpunk RED Lifestyle reference data and calendar helpers.

Only compact costs and entitlement summaries are stored here. The sourcebook
remains the authority for the full rules text (Cyberpunk RED, p. 377).
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
import re
from typing import Final


SOURCE_PAGE: Final[int] = 377
MONTH_PATTERN: Final[re.Pattern[str]] = re.compile(r"^(\d{4})-(0[1-9]|1[0-2])$")


@dataclass(frozen=True, slots=True)
class Lifestyle:
    key: str
    label: str
    monthly_cost: int
    entitlements: tuple[str, ...]
    source_page: int = SOURCE_PAGE


LIFESTYLES: Final[dict[str, Lifestyle]] = {
    "kibble": Lifestyle(
        "kibble",
        "Kibble",
        100,
        ("Basic kibble meals", "One movie or braindance per month"),
    ),
    "generic_prepak": Lifestyle(
        "generic_prepak",
        "Generic Prepak",
        300,
        ("Generic prepackaged meals", "A good bar or restaurant visit each weekend"),
    ),
    "good_prepak": Lifestyle(
        "good_prepak",
        "Good Prepak",
        600,
        ("Restaurant-quality prepackaged meals", "One live event per month"),
    ),
    "fresh_food": Lifestyle(
        "fresh_food",
        "Fresh Food",
        1_500,
        ("Fresh meals", "Executive nightlife", "One hotel stay and world-class meal per month"),
    ),
}

_ALIASES: Final[dict[str, str]] = {
    "kibble": "kibble",
    "generic prepak": "generic_prepak",
    "generic_prepak": "generic_prepak",
    "generic-prepak": "generic_prepak",
    "good prepak": "good_prepak",
    "good_prepak": "good_prepak",
    "good-prepak": "good_prepak",
    "fresh food": "fresh_food",
    "fresh_food": "fresh_food",
    "fresh-food": "fresh_food",
}


def normalize_lifestyle(value: str) -> str:
    key = _ALIASES.get(str(value).strip().lower())
    if key is None:
        choices = ", ".join(profile.label for profile in LIFESTYLES.values())
        raise ValueError(f"unknown Lifestyle: {value}; choose one of {choices}")
    return key


def lifestyle_view(key: str) -> dict[str, object]:
    profile = LIFESTYLES[normalize_lifestyle(key)]
    data = asdict(profile)
    data["entitlements"] = list(profile.entitlements)
    return data


def validate_month(value: str) -> str:
    month = str(value).strip()
    if not MONTH_PATTERN.fullmatch(month):
        raise ValueError("month must use YYYY-MM")
    return month


def next_month(value: str) -> str:
    month = validate_month(value)
    year, number = (int(part) for part in month.split("-", 1))
    if number == 12:
        return f"{year + 1:04d}-01"
    return f"{year:04d}-{number + 1:02d}"


__all__ = [
    "LIFESTYLES",
    "SOURCE_PAGE",
    "Lifestyle",
    "lifestyle_view",
    "next_month",
    "normalize_lifestyle",
    "validate_month",
]
