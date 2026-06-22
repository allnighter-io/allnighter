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


def _normalize_patches_to_champion(
    patches: dict[str, str], champion_roles: dict[str, Any]
) -> dict[str, str]:
    """Map compare-record role keys onto champion overlay keys (same skillId)."""
    by_skill = {r.get("skillId"): rkey for rkey, r in champion_roles.items()}
    out: dict[str, str] = {}
    for role_key, change in patches.items():
        skill = role_key.split("#", 1)[0]
        target = by_skill.get(skill)
        if not target:
            continue
        out[target] = change
    return out


def build_candidate_overlay(
    champion_overlay: dict[str, Any],
    *,
    compare_record: dict[str, Any],
    round_no: int,
    builtin_templates: dict[str, str] | None = None,
    controlled: bool = False,
    narrow: bool = False,
) -> dict[str, Any]:
    """Champion overlay + hypothesis patches on banked roles = material candidate arm.

    When controlled=True, only patch roles already present in the champion overlay
    (same roster / no structural adds). Unmatched structural roles in the compare
    record must be empty.
    """
    patches = hypotheses_by_role(compare_record)
    if not patches:
        raise SystemExit(
            "refusing candidate overlay: compare record has no hypothesis patches for banked roles"
        )

    champion_roles = champion_overlay.get("roles") or {}
    patches = _normalize_patches_to_champion(patches, champion_roles)
    if not patches:
        raise SystemExit(
            "refusing candidate overlay: no hypothesis patches match champion overlay roles"
        )
    if narrow:
        just_banked = set(compare_record.get("bankedRoles") or [])
        champion_banked = set(champion_overlay.get("bankedRoles") or [])
        # Prefer one unbanked role so R6 tests a single new hypothesis, not re-sweeping winners.
        candidates = [r for r in patches if r not in just_banked and r not in champion_banked]
        if not candidates:
            candidates = [r for r in patches if r not in just_banked]
        pick = candidates[0] if candidates else next(iter(patches))
        patches = {pick: patches[pick]}
    if controlled:
        unmatched = compare_record.get("unmatchedRoles") or []
        overlay_skill_ids = {r.get("skillId") for r in champion_roles.values()}
        alien = [u for u in unmatched if u.split("#", 1)[0] not in overlay_skill_ids]
        if alien:
            raise SystemExit(
                f"refusing controlled candidate: structural roles not in champion roster: {alien}"
            )

    out = deepcopy(champion_overlay)
    out["round"] = round_no
    out["arm"] = "candidate"
    out["builtAt"] = datetime.now(timezone.utc).isoformat()
    if controlled:
        out["candidatePolicy"] = "controlled_prompt_only"
    if narrow:
        out["candidatePolicy"] = "narrow_single_role"
    roles: dict[str, Any] = {}
    for rkey, role in champion_roles.items():
        new_role = dict(role)
        new_role.setdefault("originRoleKey", rkey)
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
