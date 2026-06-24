#!/usr/bin/env python3
"""Build macro composition overlays (forward-add seats, merge)."""
from __future__ import annotations

import hashlib
import json
from copy import deepcopy
from pathlib import Path
from typing import Any


def forward_add_overlay(
    base_overlay: dict[str, Any],
    donor_overlay: dict[str, Any],
    added_role_keys: list[str],
    *,
    round_no: int,
    suite_id: str,
) -> dict[str, Any]:
    """Lite (+ donor seats) with declared composition delta."""
    base_roles = base_overlay.get("roles") or {}
    donor_roles = donor_overlay.get("roles") or {}
    missing = [k for k in added_role_keys if k not in donor_roles]
    if missing:
        raise SystemExit(f"donor overlay missing roles: {missing}")
    for k in added_role_keys:
        if k in base_roles:
            raise SystemExit(f"role already on base overlay: {k}")

    out = deepcopy(base_overlay)
    out["suiteId"] = suite_id
    out["round"] = round_no
    out["promotionClass"] = "composition"
    out["macroDelta"] = {
        "kind": "forward_add",
        "addedRoles": list(added_role_keys),
        "baseTeamId": base_overlay.get("teamId"),
        "donorTeamId": donor_overlay.get("teamId"),
    }
    roles = dict(out.get("roles") or {})
    for rk in added_role_keys:
        roles[rk] = deepcopy(donor_roles[rk])
    out["roles"] = roles
    out["labTeamId"] = out.get("labTeamId") or f"lab_{out.get('teamId', 'team')}_r{round_no}_macro"
    return out


def overlay_role_keys(overlay: dict[str, Any]) -> list[str]:
    return sorted((overlay.get("roles") or {}).keys())


def overlays_material_delta(base: dict[str, Any], candidate: dict[str, Any]) -> bool:
    return overlay_role_keys(base) != overlay_role_keys(candidate) or bool(candidate.get("macroDelta"))


def config_hash_roles(overlay: dict[str, Any]) -> str:
    parts = []
    for rk in sorted(overlay.get("roles") or {}):
        role = overlay["roles"][rk]
        th = role.get("templateHash") or hashlib.sha256((role.get("template") or "").encode()).hexdigest()[:16]
        parts.append(f"{rk}|{role.get('skillId')}|{th}")
    if overlay.get("macroDelta"):
        parts.append("macro:" + json.dumps(overlay["macroDelta"], sort_keys=True))
    return hashlib.sha256("\n".join(parts).encode()).hexdigest()[:16]


def write_overlay(path: Path, overlay: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    overlay["configHash"] = config_hash_roles(overlay)
    path.write_text(json.dumps(overlay, indent=2) + "\n")


def build_lite_plus_role(
    lite_path: Path,
    full_path: Path,
    out_path: Path,
    *,
    added_role: str,
    team_suffix: str,
    round_no: int = 1,
    suite_id: str = "bug_hunt_necessity_v1",
) -> dict[str, Any]:
    lite = json.loads(lite_path.read_text())
    full = json.loads(full_path.read_text())
    overlay = forward_add_overlay(
        lite,
        full,
        [added_role],
        round_no=round_no,
        suite_id=suite_id,
    )
    overlay["teamId"] = f"code_bug_hunt_lite_plus_{team_suffix}"
    overlay["labTeamId"] = f"lab_code_bug_hunt_lite_plus_{team_suffix}_r{round_no}_candidate"
    write_overlay(out_path, overlay)
    return overlay


def build_lite_plus_trace(
    lite_path: Path,
    full_path: Path,
    out_path: Path,
    *,
    round_no: int = 1,
    suite_id: str = "bug_hunt_necessity_v1",
) -> dict[str, Any]:
    lite = json.loads(lite_path.read_text())
    full = json.loads(full_path.read_text())
    overlay = forward_add_overlay(
        lite,
        full,
        ["trace_mapper#0"],
        round_no=round_no,
        suite_id=suite_id,
    )
    overlay["teamId"] = "code_bug_hunt_lite_plus_trace"
    overlay["labTeamId"] = f"lab_code_bug_hunt_lite_plus_trace_r{round_no}_candidate"
    write_overlay(out_path, overlay)
    return overlay
