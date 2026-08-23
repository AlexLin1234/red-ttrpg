#!/usr/bin/env python3
"""Extract the item catalog from a user-owned Cyberpunk RED PDF.

Redline ships no book data. `data/items.json` holds homebrew placeholders so the
app boots with a usable catalog; a GM who owns the book runs this script to build
`data/items_local.json`, which is git-ignored and layered over the placeholders
by the ItemDB autoload at runtime. This mirrors how `tables.gd` boots on
`tables_default.gd` and lets the owner import their own values.

    python scripts/extract_items.py --pdf "/input/Cyberpunk Red.pdf"

The parser reads the printed page number off each page, so it does not depend on
a fixed cover-page offset.
"""

from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path

# Printed pages carrying item tables.
RANGED_PAGES = (341,)
MELEE_PAGES = (92,)
ARMOR_PAGES = (350,)
AMMO_PAGES = (345,)
GEAR_PAGES = (351, 352, 353, 354)
FASHION_PAGES = (356,)
DRUG_PAGES = (357,)
CYBERWARE_PAGES = (358, 359, 360, 361, 362, 363, 364, 365, 366, 367)

PRICE_TIERS = "Cheap|Everyday|Costly|Premium|Expensive|Very Expensive|V. Expensive|Super Luxury|Luxury"

# The resolver only has range bands for these types, and autofire bands for the
# two below, so every emitted weapon has to land in one of them.
RANGED_TYPES = {
    "Medium Pistol": "pistol",
    "Heavy Pistol": "pistol",
    "Very Heavy Pistol": "pistol",
    "SMG": "smg",
    "Heavy SMG": "smg",
    "Shotgun": "shotgun",
    "Assault Rifle": "assault_rifle",
    "Sniper Rifle": "sniper_rifle",
    "Bows & Crossbows": "bow",
    "Grenade Launcher": "thrown",
    "Rocket Launcher": "thrown",
}
AUTOFIRE_TYPES = {"smg", "assault_rifle"}

# Cyberware sections map onto the body parts GearMarket can install against.
CYBERWARE_PARTS = {
    "Fashionware": ["torso"],
    "Neuralware": ["head"],
    "Cyberoptics": ["eyes"],
    "Cyberaudio": ["ears"],
    "Internal Body Cyberware": ["torso"],
    "External Body Cyberware": ["torso"],
    "Cyberlimbs": ["left_arm", "right_arm"],
    "Borgware": ["torso"],
}
LIMB_PARTS = (
    ("Cyberleg", ["left_leg", "right_leg"]),
    ("Cyberfoot", ["left_leg", "right_leg"]),
    ("Cyberarm", ["left_arm", "right_arm"]),
    ("Cyberhand", ["left_hand", "right_hand"]),
    ("Subdermal Grip", ["left_hand", "right_hand"]),
)


# Column headings sit inline with the first data row once the page is flattened
# to a single line, so a captured name may carry the heading as a prefix.
HEADER_NOISE = re.compile(
    r".*(?:Master Gear List|Item Cost|Description & Data|Armor Type"
    r"|Stopping Power \(SP\)|Armor Penalty \(Minimum 0\)|Install|Name|Cost|HL)\s+",
    re.IGNORECASE,
)


def clean_name(raw: str) -> str:
    """Drop any table heading the flattened page glued onto the first name."""
    return HEADER_NOISE.sub("", raw).strip(" .·-")


def slug(name: str) -> str:
    cleaned = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return cleaned or "item"


def price_of(text: str) -> int:
    return int(text.replace(",", ""))


def page_text(pdf: Path) -> dict[int, str]:
    """Map printed page number -> page text, read off the page itself."""
    import fitz  # imported lazily so the parsers stay testable without PyMuPDF

    pages: dict[int, str] = {}
    with fitz.open(pdf) as document:
        for page in document:
            text = " ".join(page.get_text().split())
            match = re.match(r"^(\d{1,3})\b", text)
            if not match:
                match = re.search(r"\b(\d{1,3})$", text)
            if match:
                pages.setdefault(int(match.group(1)), text)
    return pages


def chunk_text(chunks: Path) -> dict[int, str]:
    """Same map, read from a previously extracted chunks.jsonl instead."""
    pages: dict[int, str] = {}
    with chunks.open(encoding="utf-8") as handle:
        for line in handle:
            record = json.loads(line)
            pages.setdefault(int(record["printed_page_start"]), record["text"])
    return pages


def join(pages: dict[int, str], wanted: tuple[int, ...]) -> str:
    return " ".join(pages.get(number, "") for number in wanted)


def parse_ranged(text: str) -> list[dict]:
    names = "|".join(re.escape(key) for key in RANGED_TYPES)
    pattern = re.compile(
        rf"\b({names})\s+(?:Handgun|Shoulder Arms|Archery|Heavy Weapons)\s+"
        rf"(\d+)d6\s+(\d+|N/A)\s*\([^)]*\)\s+(\d+)\s+\d+\s+(?:YES|NO)\s+"
        rf"([\d,]+)eb\s*\((?:{PRICE_TIERS})\)"
        rf"(?:\s*Alt\. Fire Modes & Special Features:\s*(.*?))?(?=\s*(?:{names})\s|$)",
        re.IGNORECASE,
    )
    items: list[dict] = []
    for match in pattern.finditer(text):
        name, dice, magazine, rof, cost, features = match.groups()
        weapon_type = RANGED_TYPES[name]
        autofire = -1
        if features:
            found = re.search(r"Autofire\s*\((\d+)\)", features)
            if found and weapon_type in AUTOFIRE_TYPES:
                autofire = int(found.group(1))
        items.append(
            {
                "id": slug(name),
                "name": name,
                "kind": "weapon",
                "description": f"{name} ({weapon_type.replace('_', ' ')}).",
                "price": price_of(cost),
                "weapon": {
                    "weapon_type": weapon_type,
                    "damage_dice": int(dice),
                    "damage_bonus": 0,
                    "rof": int(rof),
                    "ammo": 1 if magazine == "N/A" else int(magazine),
                    "magazine": 1 if magazine == "N/A" else int(magazine),
                    "autofire_rating": autofire,
                },
            }
        )
    return items


def parse_melee(text: str) -> list[dict]:
    pattern = re.compile(
        rf"\b((?:Light|Medium|Heavy|Very Heavy) Melee Weapon)\s+.*?"
        rf"(\d+)d6\s+(\d+)\s+(?:YES|NO)\s+([\d,]+)eb\s*\((?:{PRICE_TIERS})\)"
    )
    items: list[dict] = []
    for name, dice, rof, cost in pattern.findall(text):
        items.append(
            {
                "id": slug(name),
                "name": name,
                "kind": "weapon",
                "description": f"{name}.",
                "price": price_of(cost),
                "weapon": {
                    "weapon_type": "melee",
                    "damage_dice": int(dice),
                    "damage_bonus": 0,
                    "rof": int(rof),
                    "ammo": 1,
                    "magazine": 1,
                    "autofire_rating": -1,
                },
            }
        )
    return items


def parse_armor(text: str) -> list[dict]:
    pattern = re.compile(
        rf"\b([A-Z][A-Za-z®'\- ]{{2,24}}?)\s+(\d{{1,2}})\s+"
        rf"(None|-\d[^0-9]*?)\s*([\d,]+)eb\s*\((?:{PRICE_TIERS})\)"
    )
    items: list[dict] = []
    for name, sp, penalty, cost in pattern.findall(text):
        name = clean_name(name)
        if name.lower().startswith(("armor type", "the new street")):
            continue
        for location in ("head", "body"):
            items.append(
                {
                    "id": f"{slug(name)}_{location}",
                    "name": f"{name} ({location})",
                    "kind": "armor",
                    "description": f"{name}. Penalty: {penalty.strip() or 'None'}.",
                    "price": price_of(cost),
                    "armor": {"location": location, "sp": int(sp)},
                }
            )
    return items


# The Master Gear List is one flat table, but the Night Market generator draws
# on six distinct kinds of goods, so gear is sorted into the kinds those
# categories look for. Anything unmatched stays survival gear.
GEAR_KINDS = (
    (
        "electronics",
        (
            "agent",
            "recorder",
            "braindance",
            "bug detector",
            "computer",
            "cyberdeck",
            "cell phone",
            "synthesizer",
            "guitar",
            "instrument",
            "homing tracer",
            "memory chip",
            "amplifier",
            "radar",
            "radio",
            "scrambler",
            "smart glasses",
            "video camera",
            "virtuality",
            "techscanner",
            "scanner/",
        ),
    ),
    (
        "medical",
        ("airhypo", "cryopump", "cryotank", "medscanner", "medtech", "carepak"),
    ),
    (
        "tool",
        ("duct tape", "lock picking", "tech bag", "techtool", "grapple", "handcuffs"),
    ),
    ("food", ("food stick", "kibble", "mre")),
)

# A capture that runs into the prose after a table ends mid-sentence.
PROSE_TAIL = re.compile(
    r"\b(?:costs?|is|are|can|takes|requires|allows|provides|which|and|or|the)$",
    re.IGNORECASE,
)


def gear_kind(name: str) -> str:
    lowered = name.lower()
    for kind, needles in GEAR_KINDS:
        for needle in needles:
            if needle in lowered:
                return kind
    return "gear"


def parse_simple(text: str, kind: str) -> list[dict]:
    """Name/cost tables: the Master Gear List, Fashion, and Street Drugs."""
    pattern = re.compile(
        rf"\b([A-Z][A-Za-z0-9®™'’/()&.\- ]{{2,48}}?)\s+([\d,]+)eb\s*"
        rf"\((?:{PRICE_TIERS})\)"
    )
    items: list[dict] = []
    seen: set[str] = set()
    for name, cost in pattern.findall(text):
        name = clean_name(name)
        if len(name) < 3 or name.lower().startswith(("item cost", "cost", "the new")):
            continue
        # Prose descriptions follow the table on the same pages, so a capture can
        # land mid-sentence ("Linear Frame ss (Beta): ..."). A real entry always
        # closes the parentheses it opens.
        if name.count("(") != name.count(")") or PROSE_TAIL.search(name):
            continue
        key = slug(name)
        if key in seen:
            continue
        seen.add(key)
        items.append(
            {
                "id": key,
                "name": name,
                "kind": gear_kind(name) if kind == "gear" else kind,
                "description": name,
                "price": price_of(cost),
            }
        )
    return items


# Fashion is a matrix, not a list: styles run down the side and garment slots
# across the top, with a price in every cell. Reading it as a name/cost list
# yields junk rows built from the trailing price runs.
FASHION_SLOTS = (
    "Bottoms",
    "Top",
    "Jacket",
    "Footwear",
    "Jewelry",
    "Mirrorshades",
    "Glasses",
    "Contact Lenses",
    "Hats",
)


def parse_fashion(text: str) -> list[dict]:
    cell = rf"[\d,]+eb\s*\((?:{PRICE_TIERS})\)"
    pattern = re.compile(rf"([A-Z][A-Za-z\- ]{{3,60}}?)\s+((?:{cell}\s*){{{len(FASHION_SLOTS)}}})")
    price = re.compile(rf"([\d,]+)eb\s*\((?:{PRICE_TIERS})\)")
    items: list[dict] = []
    seen: set[str] = set()
    for style, cells in pattern.findall(text):
        style = clean_name(style)
        # The header row sits immediately before the first style, so drop any
        # slot name the capture swept up with it.
        for slot in FASHION_SLOTS:
            style = re.sub(rf"^{re.escape(slot)}\s+", "", style).strip()
        if len(style) < 3:
            continue
        costs = price.findall(cells)
        if len(costs) != len(FASHION_SLOTS):
            continue
        for slot, cost in zip(FASHION_SLOTS, costs):
            name = f"{style} {slot}"
            key = slug(name)
            if key in seen:
                continue
            seen.add(key)
            items.append(
                {
                    "id": key,
                    "name": name,
                    "kind": "fashion",
                    "description": f"{slot} in the {style} style.",
                    "price": price_of(cost),
                }
            )
    return items


def parse_cyberware(text: str) -> list[dict]:
    sections = re.split(r"[▶▶]", text)
    pattern = re.compile(
        rf"\b([A-Z][A-Za-z0-9®™'’/()&.\-\u00df\u2211\u03a3 ]{{2,44}}?)\s+(Mall|Clinic|Hospital)\s+"
        rf"(.*?)\s+([\d,]+)eb\s*\((?:{PRICE_TIERS})\)\s+(\d+)\s*\(([^)]*)\)"
    )
    items: list[dict] = []
    seen: set[str] = set()
    current = "Fashionware"
    for section in sections:
        for label in CYBERWARE_PARTS:
            if section.strip().startswith(label):
                current = label
                break
        for name, install, description, cost, loss, _dice in pattern.findall(section):
            name = clean_name(name)
            key = slug(name)
            if key in seen or len(name) < 3 or name.count("(") != name.count(")"):
                continue
            seen.add(key)
            parts = CYBERWARE_PARTS[current]
            for needle, override in LIMB_PARTS:
                if needle.lower() in name.lower():
                    parts = override
                    break
            items.append(
                {
                    "id": key,
                    "name": name,
                    "kind": "cyberware",
                    "description": " ".join(description.split())[:240],
                    "price": price_of(cost),
                    "humanity_cost": int(loss),
                    "install": install.lower(),
                    "body_parts": parts,
                }
            )
    return items


def extract(pages: dict[int, str]) -> list[dict]:
    items: list[dict] = []
    items += parse_ranged(join(pages, RANGED_PAGES))
    items += parse_melee(join(pages, MELEE_PAGES))
    items += parse_armor(join(pages, ARMOR_PAGES))
    items += parse_simple(join(pages, AMMO_PAGES), "ammo")
    items += parse_simple(join(pages, GEAR_PAGES), "gear")
    items += parse_fashion(join(pages, FASHION_PAGES))
    items += parse_simple(join(pages, DRUG_PAGES), "drug")
    items += parse_cyberware(join(pages, CYBERWARE_PAGES))

    deduped: dict[str, dict] = {}
    for item in items:
        deduped.setdefault(item["id"], item)
    return list(deduped.values())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--pdf",
        type=Path,
        default=Path(os.environ.get("SOURCEBOOK_PDF", "")),
        help="path to your own copy of the rulebook",
    )
    parser.add_argument(
        "--chunks",
        type=Path,
        help="read page text from a previously extracted chunks.jsonl instead of the PDF",
    )
    parser.add_argument("--output", type=Path, default=Path("data/items_local.json"))
    arguments = parser.parse_args()

    if arguments.chunks and arguments.chunks.is_file():
        pages = chunk_text(arguments.chunks)
    elif arguments.pdf and arguments.pdf.is_file():
        pages = page_text(arguments.pdf)
    else:
        parser.error("pass --pdf (or SOURCEBOOK_PDF), or --chunks, pointing at your own copy")

    items = extract(pages)
    if not items:
        raise SystemExit("no items parsed — is this the Cyberpunk RED core rulebook?")

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        json.dumps({"version": 1, "items": items}, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    kinds: dict[str, int] = {}
    for item in items:
        kinds[item["kind"]] = kinds.get(item["kind"], 0) + 1
    summary = ", ".join(f"{count} {kind}" for kind, count in sorted(kinds.items()))
    print(f"wrote {len(items)} items to {arguments.output} ({summary})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
