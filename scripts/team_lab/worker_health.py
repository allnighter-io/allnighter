#!/usr/bin/env python3
"""Map candidate worker failures to canonical role keys for compare/promote."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import judge as J


def origin_map_from_lab_dir(lab_dir: Path) -> dict[str, str]:
    overlay: dict[str, Any] | None = None
    for fname in ("champion-overlay.json", "candidate-overlay.json"):
        p = lab_dir / fname
        if p.exists():
            overlay = json.loads(p.read_text())
            break
    if overlay is None:
        exp_path = lab_dir / "experiment.json"
        if exp_path.exists():
            exp = json.loads(exp_path.read_text())
            op = (exp.get("teamLab") or {}).get("overlayPath")
            if op:
                op_path = Path(op)
                if op_path.exists():
                    overlay = json.loads(op_path.read_text())
    if not overlay:
        return {}

    out: dict[str, str] = {}
    for rkey, role in (overlay.get("roles") or {}).items():
        origin = role.get("originRoleKey") or rkey
        for sid in {role.get("skillId"), role.get("labSkillId")}:
            if sid:
                out[str(sid)] = origin
    return out


def failed_worker_ids(candidate_lab: Path) -> list[str]:
    eval_path = candidate_lab / "evaluation" / "evaluator-record.json"
    if eval_path.exists():
        ev = json.loads(eval_path.read_text())
        failures = ev.get("workerFailures")
        if failures:
            return list(failures)
        facts = (ev.get("outputs") or {}).get("workerFacts") or []
        from_facts = [f["workerId"] for f in facts if f.get("failedOrEmpty") and f.get("workerId")]
        if from_facts:
            return from_facts

    tr_path = candidate_lab / "team-result.json"
    if not tr_path.exists():
        return []
    tr = json.loads(tr_path.read_text())
    workers_by_id = {w["id"]: w for w in tr.get("workers", []) if w.get("id")}
    out: list[str] = []
    for ans in tr.get("workerAnswers") or []:
        wid = ans.get("workerId")
        if not wid:
            continue
        meta = workers_by_id.get(wid, {})
        if meta.get("purpose") == "plan":
            continue
        text = (ans.get("markdown") or "").strip()
        status = (ans.get("status") or "").strip().lower()
        if len(text) < 80 or status in {"failed", "timedout", "timeout", "cancelled"}:
            out.append(wid)
    return out


def failed_role_keys(candidate_lab: Path) -> list[str]:
    tr_path = candidate_lab / "team-result.json"
    if not tr_path.exists():
        return []
    tr = json.loads(tr_path.read_text())
    origins = origin_map_from_lab_dir(candidate_lab)
    roles: list[str] = []
    for wid in failed_worker_ids(candidate_lab):
        for w in tr.get("workers", []):
            if w.get("id") != wid or w.get("purpose") == "plan":
                continue
            roles.append(J.role_key(w, origins))
            break
    return sorted(set(roles))


def promotion_worker_meta(candidate_lab: Path) -> dict[str, Any]:
    failed_wids = failed_worker_ids(candidate_lab)
    failed_roles = failed_role_keys(candidate_lab)
    return {
        "failedWorkers": failed_wids,
        "failedRoleKeys": failed_roles,
    }
