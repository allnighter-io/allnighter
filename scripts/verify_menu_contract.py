#!/usr/bin/env python3
"""Validate an `alln menu --json` payload (MR-S01 / MR-S03 Works Test gates).

Usage:
  python3 scripts/verify_menu_contract.py /tmp/alln-menu.json \\
    --max-built-in-bytes 32768 --require-complete --require-unique-refs \\
    --require-selection-grade
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

USE_WHEN_MAX = 48
DONT_USE_WHEN_MAX = 72
DECLARED_TEMPLATE_VARS = {"message", "ref"}

BANNED_STUBS = {
    "Pick from menu.recipes only",
    "Pick from menu",
    "Pick from menu…",
    "Not for parallel judgment",
    "Not for mutating/write runs",
    "Do NOT use this when you need the selec…",
}


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


def template_vars(template: str) -> set[str]:
    return set(re.findall(r"\{([A-Za-z0-9_]+)\}", template))


def is_banned_stub(text: str) -> bool:
    trimmed = text.strip()
    if trimmed in BANNED_STUBS:
        return True
    if trimmed.startswith("Pick from menu"):
        return True
    return False


def check_selection_pair(
    kind: str,
    row_id: str,
    use_when: Any,
    dont_use_when: Any,
    *,
    not_equal_to: str | None = None,
) -> None:
    if not isinstance(use_when, str) or not use_when.strip():
        fail(f"{kind} {row_id}: useWhen missing/empty")
    if not isinstance(dont_use_when, str) or not dont_use_when.strip():
        fail(f"{kind} {row_id}: dontUseWhen missing/empty")
    if len(use_when) > USE_WHEN_MAX:
        fail(f"{kind} {row_id}: useWhen length {len(use_when)} > {USE_WHEN_MAX}")
    if len(dont_use_when) > DONT_USE_WHEN_MAX:
        fail(f"{kind} {row_id}: dontUseWhen length {len(dont_use_when)} > {DONT_USE_WHEN_MAX}")
    if is_banned_stub(use_when) or is_banned_stub(dont_use_when):
        fail(f"{kind} {row_id}: banned derived stub prose")
    if not_equal_to is not None and use_when.strip() == not_equal_to.strip():
        fail(f"{kind} {row_id}: useWhen equals display/title only")


def require_selection_grade(menu: dict[str, Any]) -> None:
    effects = menu.get("effectProfiles") or {}
    if not isinstance(effects, dict):
        fail("effectProfiles must be an object")

    actions = menu.get("actions") or []
    if not isinstance(actions, list) or not actions:
        fail("actions must be a non-empty array for selection-grade")
    for action in actions:
        if not isinstance(action, dict):
            fail("action row must be an object")
        aid = action.get("id", "<missing>")
        check_selection_pair("action", str(aid), action.get("useWhen"), action.get("dontUseWhen"))
        eref = action.get("effectsRef")
        if not isinstance(eref, str) or eref not in effects:
            fail(f"action {aid}: effectsRef {eref!r} does not resolve")
        for field in ("example", "validateExample"):
            val = action.get(field)
            if not isinstance(val, str) or not val.strip():
                fail(f"action {aid}: {field} missing/empty")
            unknown = template_vars(val) - DECLARED_TEMPLATE_VARS
            if unknown:
                fail(f"action {aid}: {field} undeclared template vars {sorted(unknown)}")
        if aid == "run":
            dont = action["dontUseWhen"]
            if "teams duplicate" not in dont or "teams edit" not in dont:
                fail("action run: dontUseWhen must name teams duplicate / teams edit")
            if "team start" in dont or "team hello" in dont:
                fail("action run: cross-verb anti-example leak")

    for team in menu.get("teams") or []:
        if not isinstance(team, dict):
            fail("team row must be an object")
        tid = team.get("id", "<missing>")
        check_selection_pair(
            "team",
            str(tid),
            team.get("useWhen"),
            team.get("dontUseWhen"),
            not_equal_to=team.get("displayName") if isinstance(team.get("displayName"), str) else None,
        )
        run_t = team.get("runTemplate")
        val_t = team.get("validateTemplate")
        if not isinstance(run_t, str) or not isinstance(val_t, str):
            fail(f"team {tid}: missing run/validate templates")
        if f"--team {tid}" not in run_t or f"--team {tid}" not in val_t:
            fail(f"team {tid}: templates must bind canonical team id")
        if "--dry-run" not in val_t:
            fail(f"team {tid}: validateTemplate must use --dry-run")
        for label, tmpl in (("runTemplate", run_t), ("validateTemplate", val_t)):
            unknown = template_vars(tmpl) - DECLARED_TEMPLATE_VARS
            if unknown:
                fail(f"team {tid}: {label} undeclared template vars {sorted(unknown)}")

    for model in menu.get("models") or []:
        if not isinstance(model, dict):
            fail("model row must be an object")
        mid = model.get("id", "<missing>")
        check_selection_pair(
            "model",
            str(mid),
            model.get("useWhen"),
            model.get("dontUseWhen"),
            not_equal_to=model.get("displayName") if isinstance(model.get("displayName"), str) else None,
        )
        run_t = model.get("runTemplate")
        val_t = model.get("validateTemplate")
        if not isinstance(run_t, str) or not isinstance(val_t, str):
            fail(f"model {mid}: missing run/validate templates")
        if f"--worker {mid}" not in run_t or f"--worker {mid}" not in val_t:
            fail(f"model {mid}: templates must bind canonical worker id")
        if "--dry-run" not in val_t:
            fail(f"model {mid}: validateTemplate must use --dry-run")
        for label, tmpl in (("runTemplate", run_t), ("validateTemplate", val_t)):
            unknown = template_vars(tmpl) - DECLARED_TEMPLATE_VARS
            if unknown:
                fail(f"model {mid}: {label} undeclared template vars {sorted(unknown)}")

    for recipe in menu.get("recipes") or []:
        if not isinstance(recipe, dict):
            fail("recipe row must be an object")
        rid = recipe.get("id", "<missing>")
        check_selection_pair(
            "recipe",
            str(rid),
            recipe.get("useWhen"),
            recipe.get("dontUseWhen"),
            not_equal_to=recipe.get("title") if isinstance(recipe.get("title"), str) else None,
        )

    detail = menu.get("detailTemplate")
    if isinstance(detail, str):
        unknown = template_vars(detail) - DECLARED_TEMPLATE_VARS
        if unknown:
            fail(f"detailTemplate undeclared template vars {sorted(unknown)}")

    ok("selection-grade fields authored and bounded")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("json_path", type=Path, help="Path to MenuJSON file (or - for stdin)")
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
    parser.add_argument(
        "--require-selection-grade",
        action="store_true",
        help="Require authored useWhen/dontUseWhen, templates, effectsRef (MR-S03)",
    )
    args = parser.parse_args()

    path: Path = args.json_path
    if str(path) == "-":
        raw = sys.stdin.buffer.read()
    elif path.is_file():
        raw = path.read_bytes()
    else:
        fail(f"file not found: {path}")

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

    if args.require_selection_grade:
        require_selection_grade(menu)

    print("verify_menu_contract: all checks passed")


if __name__ == "__main__":
    main()
