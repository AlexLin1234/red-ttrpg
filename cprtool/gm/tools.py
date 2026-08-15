"""The three bounded tools available to the GM agent."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Mapping

from cprtool.index.query import RulesIndex
from cprtool.rules.tables import JSONTables


DV_SCALE = (
    (9, "Simple"),
    (13, "Everyday"),
    (15, "Difficult"),
    (17, "Professional"),
    (21, "Heroic"),
    (24, "Incredible"),
    (29, "Legendary"),
)


@dataclass(frozen=True, slots=True)
class Citation:
    book: str
    section: str
    page_start: int
    page_end: int

    @property
    def label(self) -> str:
        if self.page_start == self.page_end:
            return f"{self.book}, p. {self.page_start}"
        return f"{self.book}, pp. {self.page_start}-{self.page_end}"


class GMTools:
    def __init__(self, index: RulesIndex, tables: JSONTables) -> None:
        self.index = index
        self.tables = tables
        self.citations: list[Citation] = []

    def _remember(self, citation: Citation) -> None:
        if citation not in self.citations:
            self.citations.append(citation)

    def search_rules(self, query: str, book: str | None = None) -> dict[str, Any]:
        hits = self.index.search(query, book=book, limit=6)
        results = []
        for hit in hits:
            citation = Citation(hit.book, hit.section, hit.printed_page_start, hit.printed_page_end)
            self._remember(citation)
            results.append({"text": hit.text, "citation": asdict(citation), "citation_label": citation.label})
        return {"results": results}

    def lookup_table(self, name: str, args: Mapping[str, Any]) -> dict[str, Any]:
        if name == "ranged_dv":
            result = {"dv": self.tables.ranged_dv(str(args["weapon_type"]), float(args["distance_m"])), "page": 173}
        elif name == "autofire_dv":
            result = {"dv": self.tables.autofire_dv(str(args["weapon_type"]), float(args["distance_m"])), "page": 173}
        elif name == "weapon":
            result = asdict(self.tables.weapon(str(args["name"])))
        elif name == "armor":
            result = asdict(self.tables.armor(str(args["name"])))
        elif name == "critical_injury":
            result = asdict(self.tables.critical_injury(str(args["location"]), int(args["roll"])))
        elif name == "cover":
            result = dict(self.tables.cover(str(args["example"])))
        elif name == "aimed_shot":
            result = dict(self.tables.aimed_shot(str(args["location"])))
        else:
            raise ValueError(f"unknown table: {name}")
        page = int(result["page"])
        citation = Citation("Cyberpunk Red", f"Table: {name}", page, page)
        self._remember(citation)
        return {**result, "citation": asdict(citation)}

    def propose_dv(self, description: str) -> dict[str, Any]:
        lowered = description.lower()
        if any(word in lowered for word in ("legendary", "nearly impossible", "world class")):
            dv, difficulty = 29, "Legendary"
        elif any(word in lowered for word in ("incredible", "olympic", "astonishing")):
            dv, difficulty = 24, "Incredible"
        elif any(word in lowered for word in ("heroic", "extreme", "best of the best")):
            dv, difficulty = 21, "Heroic"
        elif any(word in lowered for word in ("professional", "specialist", "expert")):
            dv, difficulty = 17, "Professional"
        elif any(word in lowered for word in ("difficult", "hard", "risky")):
            dv, difficulty = 15, "Difficult"
        elif any(word in lowered for word in ("simple", "trivial", "easy")):
            dv, difficulty = 9, "Simple"
        else:
            dv, difficulty = 13, "Everyday"
        citation = Citation("Cyberpunk Red", "Difficulty Values", 129, 129)
        self._remember(citation)
        return {
            "suggested_dv": dv,
            "difficulty": difficulty,
            "reasoning": f"Mapped the description to the printed {difficulty} difficulty tier; GM approval required.",
            "citation": asdict(citation),
        }

    def dispatch(self, name: str, arguments: Mapping[str, Any]) -> dict[str, Any]:
        if name == "search_rules":
            return self.search_rules(str(arguments["query"]), arguments.get("book"))
        if name == "lookup_table":
            return self.lookup_table(str(arguments["name"]), arguments.get("args", {}))
        if name == "propose_dv":
            return self.propose_dv(str(arguments["description"]))
        raise ValueError(f"unknown tool: {name}")


TOOL_SCHEMAS = [
    {
        "name": "search_rules",
        "description": "Search only the local Cyberpunk RED rules index and return cited passages.",
        "input_schema": {
            "type": "object",
            "properties": {"query": {"type": "string"}, "book": {"type": "string"}},
            "required": ["query"],
        },
    },
    {
        "name": "lookup_table",
        "description": "Look up an exact operator-validated table entry without arithmetic.",
        "input_schema": {
            "type": "object",
            "properties": {"name": {"type": "string"}, "args": {"type": "object"}},
            "required": ["name", "args"],
        },
    },
    {
        "name": "propose_dv",
        "description": "Suggest a printed difficulty tier for explicit GM approval; never execute it.",
        "input_schema": {
            "type": "object",
            "properties": {"description": {"type": "string"}},
            "required": ["description"],
        },
    },
]


__all__ = ["Citation", "DV_SCALE", "GMTools", "TOOL_SCHEMAS"]
