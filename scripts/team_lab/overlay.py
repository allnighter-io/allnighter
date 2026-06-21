#!/usr/bin/env python3
"""Deploy champion/candidate overlay to MCP custom team + lab skills."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from config import config_hash, overlay_material_delta
from mcp_client import MCPStdioClient, parse_tool_json
from model_policy import LEAD_OPUS, WORKER_POOL, WORKER_POOL_LABEL, apply_model_policy


class OverlayDeployError(RuntimeError):
    pass


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


def _ensure_lab_skill(client: MCPStdioClient, role: dict[str, Any]) -> str:
    """Return skill id to use on the team row (lab fork or built-in)."""
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


def _save_team_with_skill_map(
    client: MCPStdioClient,
    *,
    base_team_id: str,
    lab_team_id: str | None,
    skill_map: dict[str, str],
    display_name: str,
) -> str:
    """Duplicate if needed, wire skill_map into full TeamPreset, teams_save."""
    if lab_team_id and _team_exists(client, lab_team_id):
        team_def = _fetch_team_definition(client, lab_team_id)
    else:
        dup = parse_tool_json(
            client.call_tool(
                "teams_duplicate",
                {"teamId": base_team_id, "name": display_name},
            )
        )
        lab_team_id = dup["id"]
        team_def = _fetch_team_definition(client, lab_team_id)

    _apply_skill_map(team_def, skill_map)
    team_def["id"] = lab_team_id
    team_def["displayName"] = display_name
    team_def["builtIn"] = False
    client.call_tool("teams_save", {"teamId": lab_team_id, "definition": team_def})

    # Verify wiring — every remapped built-in skill must appear on a row.
    saved = _fetch_team_definition(client, lab_team_id)
    saved_skills = {s.get("skillId") for s in saved.get("workerSpecs", [])}
    if lead := saved.get("lead"):
        if isinstance(lead, dict) and lead.get("skillId"):
            saved_skills.add(lead["skillId"])
    for src, dst in skill_map.items():
        if src != dst and dst not in saved_skills:
            raise OverlayDeployError(
                f"teams_save did not wire lab skill {dst} (from {src}) into team {lab_team_id}"
            )
    return lab_team_id


def _verify_model_policy_definition(team_def: dict[str, Any]) -> None:
    """Confirm saved TeamPreset carries lab model routing (MCP preflight uses a stale team snapshot)."""
    lead = team_def.get("lead") or {}
    if lead.get("preferredModelId") != LEAD_OPUS:
        raise OverlayDeployError(
            f"model policy lead not wired (got {lead.get('preferredModelId')!r}, want {LEAD_OPUS})"
        )
    pool = set(WORKER_POOL)
    for spec in team_def.get("workerSpecs") or []:
        mid = spec.get("preferredModelId")
        if mid and mid not in pool:
            raise OverlayDeployError(f"model policy worker violation: {mid} not in {WORKER_POOL}")
        allowed = set(spec.get("allowedModelIds") or [])
        if allowed and not allowed.issubset(pool):
            raise OverlayDeployError(
                f"model policy allowed pool violation: {sorted(allowed - pool)}"
            )


def ensure_model_policy_team(
    client: MCPStdioClient,
    team_id: str,
    *,
    variant: str,
    round_no: int,
) -> tuple[str, dict[str, Any]]:
    """Duplicate built-in teams, then pin Opus lead + worker pool. Returns (team_id, policy meta)."""
    team_def = _fetch_team_definition(client, team_id)
    if team_def.get("builtIn"):
        dup = parse_tool_json(
            client.call_tool(
                "teams_duplicate",
                {"teamId": team_id, "name": f"Lab {variant} R{round_no} policy"},
            )
        )
        team_id = dup["id"]
        team_def = _fetch_team_definition(client, team_id)

    patched, policy_meta = apply_model_policy(team_def)
    patched["id"] = team_id
    patched["builtIn"] = False
    patched["displayName"] = f"Lab {variant} R{round_no} ({WORKER_POOL_LABEL})"
    client.call_tool("teams_save", {"teamId": team_id, "definition": patched})

    saved = _fetch_team_definition(client, team_id)
    _verify_model_policy_definition(saved)
    meta = {
        "modelPolicy": policy_meta,
        # Real bench preflight runs after MCP restart (ToolRuntime caches teams at init).
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

    skill_map: dict[str, str] = {}
    needs_custom_skills = False
    for _rkey, role in overlay.get("roles", {}).items():
        if role.get("templateChangedFromBuiltIn"):
            needs_custom_skills = True
            skill_map[role["skillId"]] = _ensure_lab_skill(client, role)
        else:
            skill_map[role["skillId"]] = role.get("labSkillId") or role["skillId"]

    if needs_custom_skills:
        lab_team_id = overlay.get("labTeamId") if arm == "champion" else overlay.get("candidateLabTeamId")
        display = f"Lab {arm.title()} R{overlay.get('round', '?')}"
        try:
            deployed = _save_team_with_skill_map(
                client,
                base_team_id=base_team_id,
                lab_team_id=lab_team_id,
                skill_map=skill_map,
                display_name=display,
            )
        except OverlayDeployError:
            raise
        except RuntimeError as e:
            raise OverlayDeployError(f"overlay deploy failed for {arm}: {e}") from e
        if arm == "champion":
            overlay["labTeamId"] = deployed
        else:
            overlay["candidateLabTeamId"] = deployed
        overlay_path.write_text(json.dumps(overlay, indent=2) + "\n")
        team_id = deployed
    else:
        team_id = base_team_id

    meta = {
        "arm": arm,
        "overlayPath": str(overlay_path),
        "deployedTeamId": team_id,
        "baseTeamId": base_team_id,
        "materialDelta": overlay_material_delta(overlay) or needs_custom_skills,
        "configHash": config_hash(overlay, deployed_team_id=team_id, arm=arm),
    }
    return team_id, meta


def deploy_champion_overlay(client: MCPStdioClient, overlay_path: Path) -> tuple[str, dict[str, Any]]:
    team_id, meta = deploy_overlay(client, overlay_path, arm="champion")
    if overlay_material_delta(load_overlay(overlay_path)) and team_id == load_overlay(overlay_path)["baseTeamId"]:
        raise OverlayDeployError(
            "overlay declares template changes but champion deployed on base team — wiring failed"
        )
    return team_id, meta
