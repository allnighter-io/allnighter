#!/usr/bin/env python3
"""Validate an `alln menu --json` payload (MR-S01 Works Test gates).

Usage:
  python3 scripts/verify_menu_contract.py /tmp/alln-menu.json \\
    --max-built-in-bytes 32768 --require-complete --require-unique-refs
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def fail(msg: str) -> None:
    print(f"verify_menu_contract: FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def ok(msg: str) -> None:
    print(f"verify_menu_contract: OK: {msg}")


def collection_refs(menu: dict[str, Any]) -> list[str]:
    refs: list[str] = []
    for cmd in menu.get("commands") or []:
        if "ref" in cmd:
            refs.append(cmd["ref"])
    for team in menu.get("teams") or []:
        if "ref" in team:
            refs.append(team["ref"])
    for model in menu.get("models") or []:
        if "ref" in model:
            refs.append(model["ref"])
    for recipe in menu.get("recipes") or []:
        if "ref" in recipe:
            refs.append(recipe["ref"])
    return refs


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("json_path", type=Path, help="Path to MenuJSON file")
    parser.add_argument(
        "--max-built-in-bytes",
        type=int,
        default=32768,
        help="Maximum UTF-8 byte size of the JSON file (default 32768)",
    )
    parser.add_argument(
        "--require-complete",
        action="store_true",
        help="Require completeness.*.complete == true for every collection",
    )
    parser.add_argument(
        "--require-unique-refs",
        action="store_true",
        help="Require unique refs across commands/teams/models/recipes",
    )
    args = parser.parse_args()

    path: Path = args.json_path
    if not path.is_file():
        fail(f"file not found: {path}")

    raw = path.read_bytes()
    size = len(raw)
    if size > args.max_built_in_bytes:
        fail(f"size {size} exceeds --max-built-in-bytes {args.max_built_in_bytes}")
    ok(f"size {size} <= {args.max_built_in_bytes}")

    try:
        menu = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON: {exc}")

    if not isinstance(menu, dict):
        fail("top-level JSON must be an object")

    if menu.get("truncated") is not False:
        fail(f"truncated must be false, got {menu.get('truncated')!r}")
    ok("truncated == false")

    completeness = menu.get("completeness")
    if not isinstance(completeness, dict):
        fail("missing completeness object")

    if args.require_complete:
        for key in ("actions", "commands", "teams", "models", "recipes", "effectProfiles"):
            entry = completeness.get(key)
            if not isinstance(entry, dict):
                fail(f"completeness.{key} missing")
            if entry.get("complete") is not True:
                fail(f"completeness.{key}.complete must be true, got {entry.get('complete')!r}")
            count = entry.get("count")
            if not isinstance(count, int) or count < 0:
                fail(f"completeness.{key}.count must be a non-negative int")
        ok("completeness booleans true")

    if args.require_unique_refs:
        refs = collection_refs(menu)
        if len(refs) != len(set(refs)):
            seen: set[str] = set()
            dupes = []
            for r in refs:
                if r in seen:
                    dupes.append(r)
                seen.add(r)
            fail(f"duplicate refs: {dupes[:10]}")
        ok(f"unique refs ({len(refs)})")

    for key in ("commands", "teams", "models", "recipes"):
        rows = menu.get(key) or []
        if not isinstance(rows, list) or len(rows) == 0:
            fail(f"{key} must be a non-empty array")
    ok("collections non-empty")

    print("verify_menu_contract: all checks passed")


if __name__ == "__main__":
    main()
