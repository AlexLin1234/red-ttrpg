"""Offline and Anthropic-backed agents sharing the same bounded tool surface."""

from __future__ import annotations

import json
import re
from dataclasses import asdict
from typing import Any, Protocol

from cprtool.gm.prompts import ADJUDICATION_PROMPT, SYSTEM_PROMPT
from cprtool.gm.tools import Citation, GMTools, TOOL_SCHEMAS
from cprtool.index.embedding import tokens
from cprtool.index.query import GENERIC_QUERY_WORDS, STOPWORDS


class Agent(Protocol):
    def ask(self, question: str, book: str | None = None) -> tuple[str, list[Citation]]: ...

    def adjudicate(self, description: str) -> dict[str, Any]: ...


COMMON_RULE_ROUTES = (
    (("oppos", "tie"), 129),
    (("everyday", "dv"), 129),
    (("natural", "ten"), 130),
    (("natural", "one"), 130),
    (("action", "turn"), 168),
    (("aim", "head"), 170),
    (("reload",), 170),
    (("ref", "dodge", "range"), 172),
    (("pistol", "dv"), 173),
    (("assault", "rifle", "magazine"), 341),
    (("autofire",), 173),
    (("suppress", "fire"), 174),
    (("shotgun", "shell"), 174),
    (("explosive", "blast"), 174),
    (("melee", "armor"), 176),
    (("chok", "grapple"), 177),
    (("partial", "cover"), 182),
    (("excess", "cover"), 182),
    (("overturn", "table"), 183),
    (("bulletproof", "shield"), 184),
    (("armorjack", "sp"), 185),
    (("armor", "ablat"), 186),
    (("serious", "wound"), 186),
    (("critical", "injury", "six"), 187),
    (("body", "critical", "injury"), 187),
    (("head", "critical", "injury"), 188),
    (("death", "save"), 188),
    (("quick", "fix", "treatment"), 223),
    (("poor", "quality", "weapon"), 342),
)


def _canonical_page(question: str) -> int | None:
    words = tokens(question)
    for stems, page in COMMON_RULE_ROUTES:
        if all(any(word.startswith(stem) for word in words) for stem in stems):
            return page
    return None


def _skill_for(description: str) -> str:
    lowered = description.lower()
    mappings = (
        (("sneak", "hide", "quiet"), "Stealth"),
        (("climb", "jump", "swim", "balance"), "Athletics"),
        (("persuade", "convince", "negotiate"), "Persuasion"),
        (("intimidate", "threaten"), "Interrogation"),
        (("drive", "car", "motorcycle"), "Drive Land Vehicle"),
        (("shoot", "pistol", "handgun"), "Handgun"),
        (("rifle", "shotgun"), "Shoulder Arms"),
        (("notice", "spot", "search"), "Perception"),
    )
    for words, skill in mappings:
        if any(word in lowered for word in words):
            return skill
    return "GM-selected relevant Skill"


class OfflineAgent:
    """A no-key extractive fallback that remains fully grounded and cited."""

    def __init__(self, tools: GMTools) -> None:
        self.tools = tools

    def ask(self, question: str, book: str | None = None) -> tuple[str, list[Citation]]:
        self.tools.citations.clear()
        payload = self.tools.search_rules(question, book)
        if not payload["results"]:
            return "The local rules index did not establish an answer.", []
        if re.search(r"\b(calculate|compute|total|roll for me|damage result)\b", question, re.I):
            labels = "; ".join(citation.label for citation in self.tools.citations[:3])
            return f"I can identify the governing rule, but computed outcomes must come from the resolver. {labels}", self.tools.citations
        query_terms = {
            token for token in tokens(question)
            if token not in STOPWORDS and token not in GENERIC_QUERY_WORDS
        }

        def overlap(searchable: str) -> int:
            searchable_terms = set(tokens(searchable))
            return sum(
                any(word.startswith(term) or (len(word) >= 4 and term.startswith(word)) for word in searchable_terms)
                for term in query_terms
            )

        def result_score(item: tuple[int, dict[str, Any]]) -> tuple[float, float]:
            rank, result = item
            searchable = f"{result['citation']['section']} {result['text']}"
            coverage = overlap(searchable) / max(1, len(query_terms))
            heading_overlap = overlap(result["citation"]["section"])
            return coverage + heading_overlap * 0.2, -rank

        canonical_page = _canonical_page(question)
        canonical = [
            result for result in payload["results"]
            if result["citation"]["page_start"] <= canonical_page <= result["citation"]["page_end"]
        ] if canonical_page is not None else []
        if canonical:
            selected = canonical[0]
        else:
            _, selected = max(enumerate(payload["results"]), key=result_score)
        selected_citation = Citation(**selected["citation"])
        self.tools.citations = [selected_citation] + [
            citation for citation in self.tools.citations if citation != selected_citation
        ]
        sentences = re.split(r"(?<=[.!?])\s+", selected["text"])
        sentences = [
            sentence for sentence in sentences
            if not re.search(r"\bfor a total of\b|\d+\s*(?:\+|\-|x|×)\s*\d+", sentence, re.I)
        ]
        ranked = sorted(
            (sentence.strip() for sentence in sentences if sentence.strip()),
            key=overlap,
            reverse=True,
        )
        excerpt = (ranked[0][:900] if ranked else "The retrieved passage contains an example calculation; use the resolver for the outcome.")
        citation = selected_citation
        return f"{excerpt} ({citation.label})", self.tools.citations

    def adjudicate(self, description: str) -> dict[str, Any]:
        self.tools.citations.clear()
        proposal = self.tools.propose_dv(description)
        return {
            "suggested_dv": proposal["suggested_dv"],
            "skill": _skill_for(description),
            "reasoning": proposal["reasoning"],
            "citations": [asdict(citation) for citation in self.tools.citations],
        }


class AnthropicAgent:
    def __init__(self, tools: GMTools, api_key: str, model: str) -> None:
        import anthropic

        self.tools = tools
        self.model = model
        self.client = anthropic.Anthropic(api_key=api_key)

    def _run(self, prompt: str) -> str:
        messages: list[dict[str, Any]] = [{"role": "user", "content": prompt}]
        self.tools.citations.clear()
        for _ in range(8):
            response = self.client.messages.create(
                model=self.model,
                max_tokens=1_200,
                system=SYSTEM_PROMPT,
                tools=TOOL_SCHEMAS,
                messages=messages,
            )
            blocks = [block.model_dump(mode="json") for block in response.content]
            messages.append({"role": "assistant", "content": blocks})
            tool_uses = [block for block in blocks if block.get("type") == "tool_use"]
            if not tool_uses:
                return "\n".join(str(block.get("text", "")) for block in blocks if block.get("type") == "text").strip()
            results = []
            for call in tool_uses:
                try:
                    output = self.tools.dispatch(str(call["name"]), call.get("input", {}))
                    content = json.dumps(output, ensure_ascii=False)
                    is_error = False
                except Exception as exc:
                    content = json.dumps({"error": str(exc)})
                    is_error = True
                results.append({"type": "tool_result", "tool_use_id": call["id"], "content": content, "is_error": is_error})
            messages.append({"role": "user", "content": results})
        raise RuntimeError("tool loop exceeded eight turns")

    def ask(self, question: str, book: str | None = None) -> tuple[str, list[Citation]]:
        scope = f" Use only book {book}." if book else ""
        answer = self._run(f"Answer this rules question: {question}.{scope}")
        return answer, list(self.tools.citations)

    def adjudicate(self, description: str) -> dict[str, Any]:
        raw = self._run(f"Adjudicate this improvised action for GM approval: {description}\n{ADJUDICATION_PROMPT}")
        match = re.search(r"\{.*\}", raw, re.S)
        if not match:
            raise ValueError("agent did not return structured adjudication JSON")
        result = json.loads(match.group(0))
        result["citations"] = [asdict(citation) for citation in self.tools.citations]
        return result


__all__ = ["Agent", "AnthropicAgent", "OfflineAgent"]
