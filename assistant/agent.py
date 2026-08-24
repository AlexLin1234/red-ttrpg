"""The one outbound request, and the citation check that keeps it honest.

Claude is given a single tool — search over the campaign's active books — and a
grounding contract. Whatever comes back, the citations shown to the Game Master
are built here from passages this request actually retrieved. A filename or page
number the model wrote itself can never reach the screen, because the model is
never asked for one: it cites passage ids, and unknown ids are discarded.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import Any

from assistant import prompts
from assistant.redaction import safe_error, register_secret
from assistant.retrieval import MAX_QUESTION_CHARS, Citation, RetrievedPassage, Retriever

# Two tiers, named by what they cost a Game Master rather than by model version,
# so a campaign file never carries a model name and never ages badly.
MODELS = {"fast": "claude-haiku-4-5", "capable": "claude-opus-5"}
DEFAULT_TIER = "capable"

MAX_TOOL_ROUNDS = 4
# A cited rules answer is a few sentences. The ceiling is a size limit on what
# the helper will hand back to Godot, not a budget the model has to ration.
MAX_ANSWER_TOKENS = 2_048
REQUEST_TIMEOUT_SECONDS = 90.0

_MARKER_GROUP = re.compile(r"\[([^\[\]]{1,60})\]")
_MARKER = re.compile(r"^[a-z]\d{1,3}$")
_SPACE_BEFORE_PUNCTUATION = re.compile(r"\s+([.,;:!?])")


class AnswerError(RuntimeError):
    """A failure the Assistant tab can explain and offer a next step for."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(slots=True)
class Answer:
    status: str
    text: str
    citations: list[Citation] = field(default_factory=list)
    searches: int = 0
    model_tier: str = DEFAULT_TIER

    def as_dict(self) -> dict[str, Any]:
        return {
            "status": self.status,
            "answer": self.text,
            "citations": [citation.as_dict() for citation in self.citations],
            "searches": self.searches,
            "model_tier": self.model_tier,
        }


class _PassageRegistry:
    """Every passage this one request retrieved, keyed by its citation marker."""

    def __init__(self) -> None:
        self._by_marker: dict[str, RetrievedPassage] = {}
        self._by_chunk: dict[int, str] = {}

    def add(self, passages: list[RetrievedPassage]) -> list[RetrievedPassage]:
        registered: list[RetrievedPassage] = []
        for passage in passages:
            marker = self._by_chunk.get(passage.passage.chunk_id)
            if marker is None:
                marker = f"c{len(self._by_marker) + 1}"
                self._by_chunk[passage.passage.chunk_id] = marker
                self._by_marker[marker] = RetrievedPassage(
                    marker=marker, passage=passage.passage, citation=passage.citation
                )
            registered.append(self._by_marker[marker])
        return registered

    def citation(self, marker: str) -> Citation | None:
        found = self._by_marker.get(marker.strip().lower())
        return found.citation if found is not None else None

    def __len__(self) -> int:
        return len(self._by_marker)


def markers_in(text: str) -> list[str]:
    """Citation markers in the order the answer first uses them."""

    found: list[str] = []
    for group in _MARKER_GROUP.findall(text):
        for candidate in re.split(r"[,\s]+", group.strip().lower()):
            if _MARKER.fullmatch(candidate) and candidate not in found:
                found.append(candidate)
    return found


def strip_markers(text: str) -> str:
    """Remove marker groups; the citations are shown as their own list."""

    def replace(match: re.Match[str]) -> str:
        parts = re.split(r"[,\s]+", match.group(1).strip().lower())
        return "" if parts and all(_MARKER.fullmatch(part) for part in parts) else match.group(0)

    cleaned = _MARKER_GROUP.sub(replace, text)
    cleaned = _SPACE_BEFORE_PUNCTUATION.sub(r"\1", cleaned)
    return re.sub(r"[ \t]{2,}", " ", cleaned).strip()


def format_passages(passages: list[RetrievedPassage]) -> str:
    if not passages:
        return prompts.NO_RESULTS
    blocks = [prompts.PASSAGE_TEMPLATE.format(marker=passage.marker, text=passage.text) for passage in passages]
    return "\n".join([prompts.TOOL_RESULT_PREAMBLE, *blocks])


class RulesAssistant:
    """Answers one question at a time, grounded in the active books."""

    def __init__(
        self,
        retriever: Retriever,
        api_key: str,
        tier: str = DEFAULT_TIER,
        client: Any | None = None,
    ) -> None:
        self.retriever = retriever
        self.tier = tier if tier in MODELS else DEFAULT_TIER
        self.model = MODELS[self.tier]
        self._api_key = api_key
        self._client = client
        if api_key:
            register_secret(api_key)

    def _messages_client(self) -> Any:
        if self._client is not None:
            return self._client
        if not self._api_key:
            raise AnswerError("missing_key", "Add your Anthropic API key in Assistant Setup.")
        try:
            import anthropic
        except ImportError as exc:  # pragma: no cover - depends on the install
            raise AnswerError(
                "helper_incomplete", "This Redline installation is missing the Anthropic client."
            ) from exc
        self._client = anthropic.Anthropic(api_key=self._api_key, timeout=REQUEST_TIMEOUT_SECONDS, max_retries=2)
        return self._client

    def verify_key(self) -> str:
        """Check the stored key against Anthropic without spending tokens.

        Retrieving the model description authenticates the key and confirms the
        chosen model is reachable, which is exactly what the setup tab claims to
        have tested.
        """

        client = self._messages_client()
        try:
            client.models.retrieve(self.model)
        except Exception as exc:
            raise self._transport_error(exc) from exc
        return self.model

    def ask(self, question: str, books: list[Any]) -> Answer:
        asked = (question or "").strip()
        if len(asked) < 3:
            raise AnswerError("empty_question", "Ask a rules question first.")
        if len(asked) > MAX_QUESTION_CHARS:
            raise AnswerError(
                "question_too_long",
                f"Questions are limited to {MAX_QUESTION_CHARS} characters.",
            )
        if not books:
            raise AnswerError(
                "no_active_books",
                "This campaign has no active rulebooks. Choose one in the Assistant tab.",
            )

        registry = _PassageRegistry()
        client = self._messages_client()
        messages: list[dict[str, Any]] = [{"role": "user", "content": asked}]
        searches = 0

        for _ in range(MAX_TOOL_ROUNDS):
            response = self._create(client, messages)
            blocks = [self._block_dict(block) for block in response.content]
            messages.append({"role": "assistant", "content": blocks})
            tool_uses = [block for block in blocks if block.get("type") == "tool_use"]
            if not tool_uses:
                text = "\n".join(str(block.get("text", "")) for block in blocks if block.get("type") == "text").strip()
                return self._finish(text, registry, searches)
            results = []
            for call in tool_uses:
                searches += 1
                results.append(
                    {
                        "type": "tool_result",
                        "tool_use_id": call.get("id"),
                        "content": self._run_search(call, books, registry),
                    }
                )
            messages.append({"role": "user", "content": results})

        raise AnswerError("search_loop", "The assistant kept searching without answering. Try a narrower question.")

    # -- internals ----------------------------------------------------------

    def _create(self, client: Any, messages: list[dict[str, Any]]) -> Any:
        try:
            return client.messages.create(
                model=self.model,
                max_tokens=MAX_ANSWER_TOKENS,
                system=prompts.SYSTEM_PROMPT,
                tools=[prompts.SEARCH_TOOL],
                messages=messages,
            )
        except Exception as exc:
            raise self._transport_error(exc) from exc

    @staticmethod
    def _transport_error(exc: Exception) -> AnswerError:
        try:
            import anthropic
        except ImportError:  # pragma: no cover - depends on the install
            return AnswerError("service_error", safe_error(exc, "the request to Anthropic failed"))
        if isinstance(exc, anthropic.AuthenticationError):
            return AnswerError("invalid_key", "Anthropic rejected that API key. Check it in Assistant Setup.")
        if isinstance(exc, anthropic.PermissionDeniedError):
            return AnswerError("invalid_key", "That API key is not allowed to use the Messages API.")
        if isinstance(exc, anthropic.RateLimitError):
            return AnswerError("rate_limited", "Anthropic is rate-limiting this key. Wait a moment and ask again.")
        if isinstance(exc, anthropic.APIConnectionError):
            return AnswerError("offline", "Redline could not reach Anthropic. Check the network and ask again.")
        if isinstance(exc, anthropic.APIStatusError):
            if exc.status_code >= 500:
                return AnswerError("service_error", "Anthropic is unavailable right now. Ask again shortly.")
            return AnswerError("service_error", safe_error(exc, "Anthropic rejected the request"))
        return AnswerError("service_error", safe_error(exc, "the request to Anthropic failed"))

    @staticmethod
    def _block_dict(block: Any) -> dict[str, Any]:
        if isinstance(block, dict):
            return block
        dumper = getattr(block, "model_dump", None)
        return dumper(mode="json") if callable(dumper) else dict(block)

    def _run_search(self, call: dict[str, Any], books: list[Any], registry: _PassageRegistry) -> str:
        raw = call.get("input", {})
        # Tool input arrives as JSON; never string-match the serialized form.
        arguments = json.loads(raw) if isinstance(raw, str) else dict(raw)
        query = str(arguments.get("query", "")).strip()
        if not query:
            return prompts.NO_RESULTS
        found = registry.add(self.retriever.search(query, books))
        return format_passages(found)

    def _finish(self, text: str, registry: _PassageRegistry, searches: int) -> Answer:
        body = text.strip()
        if not body:
            raise AnswerError("empty_answer", "The assistant returned nothing. Ask again.")
        if body.upper().startswith(prompts.UNSUPPORTED_SENTINEL):
            note = strip_markers(body[len(prompts.UNSUPPORTED_SENTINEL) :].strip(" :\n-"))
            answer = f"{prompts.UNSUPPORTED_ANSWER}\n\n{note}" if note else prompts.UNSUPPORTED_ANSWER
            return Answer("unsupported", answer, [], searches, self.tier)

        citations: list[Citation] = []
        for marker in markers_in(body):
            citation = registry.citation(marker)
            if citation is not None and citation not in citations:
                citations.append(citation)
        if not citations:
            # An answer with nothing behind it is worse than no answer, so it is
            # never shown — whether the model skipped its markers or invented them.
            return Answer("unsupported", prompts.UNSUPPORTED_ANSWER, [], searches, self.tier)
        return Answer("answered", strip_markers(body), citations, searches, self.tier)


__all__ = [
    "Answer",
    "AnswerError",
    "DEFAULT_TIER",
    "MAX_ANSWER_TOKENS",
    "MAX_TOOL_ROUNDS",
    "MODELS",
    "RulesAssistant",
    "format_passages",
    "markers_in",
    "strip_markers",
]
