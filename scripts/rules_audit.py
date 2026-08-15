"""Interactively confirm every pure-resolver constant against the corebook."""

from __future__ import annotations

import argparse
import ast
from pathlib import Path


DEFAULT_RESOLVER = Path(__file__).parents[1] / "cprtool" / "rules" / "resolver.py"


def audited_rules(path: Path) -> list[tuple[str, object, str]]:
    source = path.read_text(encoding="utf-8")
    lines = source.splitlines()
    tree = ast.parse(source)
    for node in tree.body:
        if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.target.id == "RULES":
            if not isinstance(node.value, ast.Dict):
                raise ValueError("RULES must be a literal dictionary")
            results = []
            for key, value in zip(node.value.keys, node.value.values, strict=True):
                name = ast.literal_eval(key)
                current = ast.literal_eval(value)
                comment = lines[value.lineno - 1].partition("#")[2].strip()
                results.append((name, current, comment))
            return results
    raise ValueError("RULES dictionary not found")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resolver", type=Path, default=DEFAULT_RESOLVER)
    parser.add_argument("--check", action="store_true", help="fail if a rule lacks a page citation")
    args = parser.parse_args(argv)
    rules = audited_rules(args.resolver)
    missing = [name for name, _, comment in rules if "p." not in comment.lower()]
    for name, value, comment in rules:
        print(f"{name} = {value!r}  # {comment or 'MISSING CITATION'}")
        if not args.check:
            answer = input("Confirm, or enter a corrected value/page note [Enter=confirm]: ").strip()
            if answer:
                print(f"  RECORD MANUALLY: {answer}")
    if missing:
        print(f"Missing page citations: {', '.join(missing)}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
