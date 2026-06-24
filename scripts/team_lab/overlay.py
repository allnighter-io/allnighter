#!/usr/bin/env python3
"""Deploy champion/candidate overlay to MCP custom team + lab skills."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from config import config_hash, overlay_material_delta
from mcp_client import MCPStdioClient, parse_tool_json
from model_policy import (
    BLOCKED_WORKER_MODELS,
    CODE_WORKER_POOL,
    DESIGN_LAB_WORKER_POOL,
    LEAD_OPUS,
    SONNET_WORKER,
    apply_model_policy,
)

LAB_TYPE_TAG = "lab"


class OverlayDeployError(RuntimeError):
    pass


def lab_isolated_teams_enabled() -> bool:
    """Default: experiment teams are isolated lab_ ids, never user-facing production teams.

    Set ALLN_LAB_IN_PLACE=1 only for founder-approved upgrades to the real team id.
    """
    if os.environ.get("ALLN_LAB_IN_PLACE", "").lower() in ("1", "true", "yes"):
        return False
    return os.environ.get("ALLN_LAB_ISOLATED_TEAMS", "1").lower() not in ("0", "false", "off", "no")


def lab_team_id(base_team_id: str, round_no: int, arm: str) -> str:
    """Stable isolated team id for A/B arms, e.g. lab_code_bug_hunt_r4_champion."""
    arm_slug = arm.replace("-", "_").lower()
    return f"lab_{base_team_id}_r{round_no}_{arm_slug}"


def lab_team_id_for_overlay(overlay: dict[str, Any], round_no: int, arm: str) -> str:
    """Isolated team id keyed by overlay roster (lite vs full), not only baseTeamId."""
    slug = overlay.get("teamId") or overlay.get("baseTeamId") or "team"
    arm_slug = arm.replace("-", "_").lower()
    return f"lab_{slug}_r{round_no}_{arm_slug}"


def overlay_display_name(overlay: dict[str, Any], base_display: str) -> str:
    tid = overlay.get("teamId")
    base = overlay.get("baseTeamId")
    if tid and base and tid != base:
        label = tid.replace("code_", "").replace("_", " ").title()
        return f"{label} · Lab"
    return f"{base_display} · Lab"


def _overlay_target_skill_ids(overlay: dict[str, Any], skill_map: dict[str, str]) -> set[str]:
    allowed: set[str] = set()
    for role in (overlay.get("roles") or {}).values():
        sid = role.get("skillId")
        if not sid:
            continue
        allowed.add(sid)
        allowed.add(skill_map.get(sid, sid))
    overlay_skills = {r.get("skillId") for r in (overlay.get("roles") or {}).values()}
    for src, dst in skill_map.items():
        if src in overlay_skills:
            allowed.add(dst)
    return allowed


def _restrict_worker_specs_to_overlay(
    team_def: dict[str, Any],
    overlay: dict[str, Any],
    skill_map: dict[str, str],
) -> int:
    """Keep only worker rows declared in the overlay roles map."""
    allowed = _overlay_target_skill_ids(overlay, skill_map)
    specs = [s for s in (team_def.get("workerSpecs") or []) if s.get("skillId") in allowed]
    team_def["workerSpecs"] = specs
    return len(specs)


def load_overlay(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def _skill_exists(client: MCPStdioClient, skill_id: str) -> bool:
    try:
        client.call_tool("skills_show", {"skillId": skill_id})
        return True
    except RuntimeError as e:
        if "SKILL_NOT_FOUND" in str(e):
            return False
        raise


def _team_exists(client: MCPStdioClient, team_id: str) -> bool:
    try:
        client.call_tool("teams_show", {"teamId": team_id})
        return True
    except RuntimeError as e:
        if "TEAM_NOT_FOUND" in str(e) or "teamId required" in str(e):
            return False
        raise


def _fetch_team_definition(client: MCPStdioClient, team_id: str) -> dict[str, Any]:
    tools = client.request("tools/list")
    names = {t["name"] for t in tools.get("tools", [])}
    if "teams_definition" not in names:
        raise OverlayDeployError(
            "MCP missing teams_definition — rebuild alln; cannot wire lab skill rows"
        )
    return parse_tool_json(client.call_tool("teams_definition", {"teamId": team_id}))


def _mark_lab_team(team_def: dict[str, Any], *, display_name: str) -> None:
    tags = list(team_def.get("typeTags") or [])
    if LAB_TYPE_TAG not in tags:
        tags.append(LAB_TYPE_TAG)
    team_def["typeTags"] = tags
    team_def["displayName"] = display_name
    team_def["builtIn"] = False
    team_def["isDefaultForLane"] = False
    team_def["isDefaultForRun"] = False


def _ensure_lab_skill(client: MCPStdioClient, role: dict[str, Any], *, origin_role_key: str) -> str:
    """Return skill id to use on the team row (lab fork or built-in)."""
    role.setdefault("originRoleKey", origin_role_key)
    skill_id = role["skillId"]
    if not role.get("templateChangedFromBuiltIn"):
        return skill_id

    dup = parse_tool_json(
        client.call_tool(
            "skills_duplicate",
            {"skillId": skill_id, "name": f"Lab {role.get('skillName', skill_id)}"},
        )
    )
    actual_id = dup["id"]
    definition = {
        "id": actual_id,
        "displayName": dup.get("displayName", role.get("skillName", skill_id)),
        "lane": dup.get("lane", "code"),
        "purpose": dup.get("purpose", "answer"),
        "template": role.get("template") or dup.get("template", ""),
        "builtIn": False,
    }
    client.call_tool("skills_save", {"skillId": actual_id, "definition": definition})
    role["labSkillId"] = actual_id
    return actual_id


def _apply_skill_map(team_def: dict[str, Any], skill_map: dict[str, str]) -> None:
    for spec in team_def.get("workerSpecs", []):
        row_id = spec.get("id")
        sid = spec.get("skillId")
        if row_id and row_id in skill_map:
            spec["skillId"] = skill_map[row_id]
        elif sid in skill_map:
            spec["skillId"] = skill_map[sid]
    lead = team_def.get("lead")
    if isinstance(lead, dict):
        ls = lead.get("skillId")
        if ls in skill_map:
            lead["skillId"] = skill_map[ls]


def _seed_lab_team_from_base(
    client: MCPStdioClient,
    *,
    base_team_id: str,
    lab_team_id: str,
    display_name: str,
) -> dict[str, Any]:
    """Create a new lab_* team from a built-in/custom base (MCP allows lab_ upsert)."""
    base_def = _fetch_team_definition(client, base_team_id)
    team_def = dict(base_def)
    team_def["id"] = lab_team_id
    _mark_lab_team(team_def, display_name=display_name)
    client.call_tool("teams_save", {"teamId": lab_team_id, "definition": team_def})
    return _fetch_team_definition(client, lab_team_id)


def _save_team_with_skill_map(
    client: MCPStdioClient,
    *,
    base_team_id: str,
    target_team_id: str,
    skill_map: dict[str, str],
    display_name: str,
    isolated: bool,
    overlay: dict[str, Any],
) -> str:
    """Wire skill_map into TeamPreset and teams_save. Isolated runs use lab_* ids."""
    if isolated:
        if _team_exists(client, target_team_id):
            team_def = _fetch_team_definition(client, target_team_id)
        else:
            team_def = _seed_lab_team_from_base(
                client,
                base_team_id=base_team_id,
                lab_team_id=target_team_id,
                display_name=display_name,
            )
    elif _team_exists(client, target_team_id):
        team_def = _fetch_team_definition(client, target_team_id)
    else:
        dup = parse_tool_json(
            client.call_tool(
                "teams_duplicate",
                {"teamId": base_team_id, "name": display_name},
            )
        )
        target_team_id = dup["id"]
        team_def = _fetch_team_definition(client, target_team_id)

    _apply_skill_map(team_def, skill_map)
    _restrict_worker_specs_to_overlay(team_def, overlay, skill_map)
    team_def["id"] = target_team_id
    if isolated:
        _mark_lab_team(team_def, display_name=display_name)
    else:
        team_def["displayName"] = display_name
        team_def["builtIn"] = False
    client.call_tool("teams_save", {"teamId": target_team_id, "definition": team_def})

    saved = _fetch_team_definition(client, target_team_id)
    saved_skills = {s.get("skillId") for s in saved.get("workerSpecs", [])}
    if lead := saved.get("lead"):
        if isinstance(lead, dict) and lead.get("skillId"):
            saved_skills.add(lead["skillId"])
    for src, dst in skill_map.items():
        if src != dst and dst not in saved_skills:
            raise OverlayDeployError(
                f"teams_save did not wire lab skill {dst} (from {src}) into team {target_team_id}"
            )
    expected_workers = len(overlay.get("roles") or {})
    actual_workers = len(saved.get("workerSpecs") or [])
    if actual_workers != expected_workers:
        raise OverlayDeployError(
            f"roster trim failed: overlay declares {expected_workers} roles, "
            f"team has {actual_workers} workerSpecs"
        )
    return target_team_id


def _verify_model_policy_definition(team_def: dict[str, Any]) -> None:
    """Confirm saved TeamPreset carries lab model routing (MCP preflight uses a stale team snapshot)."""
    lead = team_def.get("lead") or {}
    if lead.get("preferredModelId") != LEAD_OPUS:
        raise OverlayDeployError(
            f"model policy lead not wired (got {lead.get('preferredModelId')!r}, want {LEAD_OPUS})"
        )
    lane = str(team_def.get("lane") or "code")
    pool = set(DESIGN_LAB_WORKER_POOL if lane == "design" else CODE_WORKER_POOL)
    sonnet_at = 2 if lane != "design" else None
    sonnet_count = 0
    for spec in team_def.get("workerSpecs") or []:
        mid = spec.get("preferredModelId")
        if mid in BLOCKED_WORKER_MODELS:
            raise OverlayDeployError(f"model policy blocked worker model: {mid}")
        if mid and mid not in pool:
            raise OverlayDeployError(f"model policy worker violation: {mid} not in {sorted(pool)}")
        if mid == SONNET_WORKER:
            sonnet_count += 1
        allowed = set(spec.get("allowedModelIds") or [])
        if allowed and not allowed.issubset(pool):
            raise OverlayDeployError(
                f"model policy allowed pool violation: {sorted(allowed - pool)}"
            )
        if allowed & BLOCKED_WORKER_MODELS:
            raise OverlayDeployError(
                f"model policy blocked allowedModelIds: {sorted(allowed & BLOCKED_WORKER_MODELS)}"
            )
    if sonnet_at is not None and sonnet_count > 1:
        raise OverlayDeployError(f"model policy: Sonnet on {sonnet_count} seats (max 1)")


def ensure_model_policy_team(
    client: MCPStdioClient,
    team_id: str,
    *,
    variant: str,
    round_no: int,
) -> tuple[str, dict[str, Any]]:
    """Pin Opus lead + worker pool on the experiment team. Never renames production teams."""
    team_def = _fetch_team_definition(client, team_id)
    original_name = team_def.get("displayName", team_id)

    patched, policy_meta = apply_model_policy(team_def)
    patched["id"] = team_id
    if team_id.startswith("lab_") or lab_isolated_teams_enabled():
        _mark_lab_team(patched, display_name=f"{original_name.split(' · Lab')[0]} · Lab")
    else:
        patched["builtIn"] = team_def.get("builtIn", False)
        patched["displayName"] = original_name
    client.call_tool("teams_save", {"teamId": team_id, "definition": patched})

    saved = _fetch_team_definition(client, team_id)
    _verify_model_policy_definition(saved)
    meta = {
        "modelPolicy": policy_meta,
        "preflightCanStart": None,
        "readyWorkers": None,
    }
    return team_id, meta


def deploy_overlay(
    client: MCPStdioClient,
    overlay_path: Path,
    *,
    arm: str,
) -> tuple[str, dict[str, Any]]:
    """Deploy overlay; return (team_id, teamLab metadata)."""
    overlay = load_overlay(overlay_path)
    base_team_id = overlay["baseTeamId"]
    arm = arm or overlay.get("arm") or "champion"
    round_no = int(overlay.get("round") or 0)
    isolated = lab_isolated_teams_enabled()

    base_def = _fetch_team_definition(client, base_team_id)
    base_display = base_def.get("displayName", base_team_id)
    lab_display = overlay_display_name(overlay, base_display)

    skill_map: dict[str, str] = {}
    needs_custom_skills = False
    for rkey, role in overlay.get("roles", {}).items():
        role.setdefault("originRoleKey", rkey)
        if role.get("templateChangedFromBuiltIn"):
            needs_custom_skills = True
            skill_map[role["skillId"]] = _ensure_lab_skill(client, role, origin_role_key=rkey)
        else:
            skill_map[role["skillId"]] = role.get("labSkillId") or role["skillId"]

    if isolated:
        target_team_id = lab_team_id_for_overlay(overlay, round_no, arm)
        display = lab_display
    else:
        target_team_id = base_team_id
        display = base_display

    if needs_custom_skills or isolated:
        try:
            deployed = _save_team_with_skill_map(
                client,
                base_team_id=base_team_id,
                target_team_id=target_team_id,
                skill_map=skill_map,
                display_name=display,
                isolated=isolated,
                overlay=overlay,
            )
        except OverlayDeployError:
            raise
        except RuntimeError as e:
            raise OverlayDeployError(f"overlay deploy failed for {arm}: {e}") from e
        if isolated:
            overlay_key = "labTeamId" if arm == "champion" else "candidateLabTeamId"
            overlay[overlay_key] = deployed
            overlay_path.write_text(json.dumps(overlay, indent=2) + "\n")
        team_id = deployed
    else:
        team_id = base_team_id

    meta = {
        "arm": arm,
        "overlayPath": str(overlay_path),
        "deployedTeamId": team_id,
        "baseTeamId": base_team_id,
        "isolatedLabTeam": isolated,
        "materialDelta": overlay_material_delta(overlay) or needs_custom_skills,
        "configHash": config_hash(overlay, deployed_team_id=team_id, arm=arm),
    }
    return team_id, meta


def deploy_champion_overlay(client: MCPStdioClient, overlay_path: Path) -> tuple[str, dict[str, Any]]:
    team_id, meta = deploy_overlay(client, overlay_path, arm="champion")
    overlay = load_overlay(overlay_path)
    if overlay_material_delta(overlay) and team_id == overlay["baseTeamId"] and lab_isolated_teams_enabled():
        raise OverlayDeployError(
            "overlay declares template changes but champion deployed on base team — wiring failed"
        )
    return team_id, meta
