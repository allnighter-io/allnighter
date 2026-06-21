#!/usr/bin/env python3
"""Team-lab config hashing — detect material champion vs candidate deltas."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


def role_lines(roles: dict[str, Any]) -> list[str]:
    lines: list[str] = []
    for rkey in sorted(roles):
        role = roles[rkey]
        skill = role.get("labSkillId") or role.get("skillId") or ""
        th = role.get("templateHash") or hashlib.sha256((role.get("template") or "").encode()).hexdigest()[:16]
        lines.append(f"{rkey}|{skill}|{th}|{role.get('provenance', '')}")
    return lines


def config_hash(
    overlay: dict[str, Any],
    *,
    deployed_team_id: str,
    arm: str,
) -> str:
    """Stable hash of the material team config an arm actually runs."""
    parts = role_lines(overlay.get("roles") or {})
    parts.append(f"team:{deployed_team_id}")
    parts.append(f"arm:{arm}")
    if overlay.get("candidateDelta"):
        parts.append("delta:" + json.dumps(overlay["candidateDelta"], sort_keys=True))
    body = "\n".join(parts)
    return hashlib.sha256(body.encode()).hexdigest()[:16]


def overlay_material_delta(overlay: dict[str, Any]) -> bool:
    """True when overlay declares a non-built-in template or explicit delta."""
    if overlay.get("candidateDelta"):
        return True
    return any(r.get("templateChangedFromBuiltIn") for r in (overlay.get("roles") or {}).values())


def read_lab_team_config(lab_dir: Path) -> dict[str, Any] | None:
    exp_path = lab_dir / "experiment.json"
    if not exp_path.exists():
        return None
    exp = json.loads(exp_path.read_text())
    return exp.get("teamLab")


def hashes_from_labs(champion_lab: Path, candidate_lab: Path) -> tuple[str | None, str | None]:
    c = read_lab_team_config(champion_lab)
    d = read_lab_team_config(candidate_lab)
    return (c.get("configHash") if c else None, d.get("configHash") if d else None)
