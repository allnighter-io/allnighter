#!/usr/bin/env python3
"""Build a candidate overlay with a declared material delta (hypothesis patches)."""
from __future__ import annotations

import hashlib
import json
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _template_hash(template: str) -> str:
    return hashlib.sha256(template.strip().encode()).hexdigest()[:16]


def apply_hypothesis_patch(template: str, change: str) -> str:
    patch = change.strip()
    if not patch:
        return template
    return template.rstrip() + "\n\n" + patch


def hypotheses_by_role(compare_record: dict[str, Any]) -> dict[str, str]:
    """First hypothesis change per role from compare-record."""
    out: dict[str, str] = {}
    banked = set(compare_record.get("bankedRoles") or [])
    for entry in compare_record.get("hypotheses") or []:
        role = entry.get("role")
        hyps = entry.get("hypotheses") or []
        if not role or not hyps:
            continue
        # Prefer banked roles; still allow explicit patches on others when listed.
        if role not in banked and role not in out:
            pass
        change = (hyps[0] or {}).get("change") or ""
        if change and (role in banked or role not in out):
            out[role] = change
    return out


def build_candidate_overlay(
    champion_overlay: dict[str, Any],
    *,
    compare_record: dict[str, Any],
    round_no: int,
    builtin_templates: dict[str, str] | None = None,
) -> dict[str, Any]:
    """Champion overlay + hypothesis patches on banked roles = material candidate arm."""
    patches = hypotheses_by_role(compare_record)
    if not patches:
        raise SystemExit(
            "refusing candidate overlay: compare record has no hypothesis patches for banked roles"
        )

    out = deepcopy(champion_overlay)
    out["round"] = round_no
    out["arm"] = "candidate"
    out["builtAt"] = datetime.now(timezone.utc).isoformat()
    roles: dict[str, Any] = {}
    for rkey, role in (out.get("roles") or {}).items():
        new_role = dict(role)
        if rkey in patches:
            template = apply_hypothesis_patch(role.get("template") or "", patches[rkey])
            builtin = (builtin_templates or {}).get(role.get("skillId", ""), "")
            changed = template.strip() != builtin.strip()
            new_role["template"] = template
            new_role["templateHash"] = _template_hash(template)
            new_role["templateChangedFromBuiltIn"] = changed
            new_role["labSkillId"] = (
                f"lab_{out.get('teamId', 'team')}_cand_r{round_no}_{role.get('skillId')}"
                if changed
                else role.get("skillId")
            )
            new_role["provenance"] = "candidate_hypothesis"
        roles[rkey] = new_role

    out["roles"] = roles
    out["candidateDelta"] = {
        "kind": "hypothesis_patch",
        "sourceCompare": compare_record.get("_path"),
        "patchedRoles": sorted(patches),
        "patches": patches,
    }
    return out


def write_candidate_overlay(path: Path, overlay: dict[str, Any]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(overlay, indent=2) + "\n")
    return path
