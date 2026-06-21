#!/usr/bin/env python3
"""Champion promotion from compare evidence — no founder approval for routine wins.

    python3 scripts/team_lab/promote.py \\
        --compare-record .lab/.../evaluation/compare-record.json \\
        --baseline-lab .lab/code_bug_hunt_champion-r2_... \\
        --candidate-lab .lab/code_bug_hunt_candidate-r2_... \\
        --suite bug_hunt_repo_regressions_v1 \\
        --team code_bug_hunt \\
        --round 3

Reads compare-record.json, validates the autopromote gate, merges banked roles into
the champion overlay (incumbent for all others), writes a promotion record, optional
reviewable skill patch, and the next-round manifest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import judge as J  # noqa: E402
from config import config_hash, hashes_from_labs, overlay_material_delta  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
CHAMPIONS_DIR = REPO / "docs/team-lab/champions"
PATCHES_DIR = REPO / "docs/team-lab/patches"
PROMOTIONS_DIR = REPO / ".lab/promotions"
DEFAULT_ALLN = REPO / "Packages/AllnighterCore/.build/debug/alln"


def repo_alln() -> Path:
    import os

    env = os.environ.get("ALLN_BIN")
    return Path(env) if env else DEFAULT_ALLN


def fetch_skill_template(alln: Path, skill_id: str) -> str:
    proc = subprocess.run(
        [str(alln), "skills", "show", skill_id, "--json"],
        capture_output=True,
        text=True,
        cwd=str(REPO),
    )
    if proc.returncode != 0:
        raise RuntimeError(f"skills show {skill_id} failed: {proc.stderr[:300]}")
    data = json.loads(proc.stdout)
    return (data.get("template") or "").strip()


def extract_skill_template(snapshot: str, builtin_template: str) -> str:
    """Skill template only — strip per-run case prompt suffix from snapshot."""
    snap = snapshot.strip()
    builtin = builtin_template.strip()
    if not snap:
        return builtin
    if snap == builtin or snap.startswith(builtin + "\n"):
        return builtin
    if builtin and snap.startswith(builtin[: min(120, len(builtin))]):
        # Snapshot is template + optional case block; prefer built-in canonical text.
        return builtin
    # Custom fork already in snapshot — take prefix before case injection heuristics.
    for marker in ("\n\nThe Team Lab", "\n\nWe have tried", "\n\nReview docs/"):
        if marker in snap:
            prefix = snap.split(marker, 1)[0].strip()
            if len(prefix) >= len(builtin) * 0.4:
                return prefix
    return snap


def load_workers(lab_dir: Path) -> dict[str, dict[str, Any]]:
    tr = json.loads((lab_dir / "team-result.json").read_text())
    out: dict[str, dict[str, Any]] = {}
    for w in tr.get("workers", []):
        if w.get("purpose") == "plan":
            continue
        out[J.role_key(w)] = w
    return out


def autopromote_gate(record: dict[str, Any]) -> tuple[str, str | None]:
    """Return (verdict, reason) where verdict is promote | escalate | hold."""
    if record.get("judgeMode") != "live":
        return "hold", "judgeMode is not live"
    if not record.get("evidenceValid"):
        return "hold", "evidenceValid is false"
    if not record.get("sameInput"):
        return "hold", "sameInput is false"
    if record.get("unmatchedRoles"):
        return "escalate", f"structural role mismatch: {record['unmatchedRoles']}"
    if record.get("interactionWarning"):
        return "escalate", "interactionWarning — deliverable regressed while roles banked"

    champ_hash = record.get("championConfigHash")
    cand_hash = record.get("candidateConfigHash")
    if not champ_hash or not cand_hash:
        return "hold", "missing championConfigHash or candidateConfigHash in compare record"
    if champ_hash == cand_hash:
        return "hold", "no material candidate delta"
    if record.get("materialCandidateDelta") is False:
        return "hold", "no material candidate delta"

    banked = record.get("bankedRoles") or []
    deliverable = record.get("deliverableOutcome")

    if not banked:
        return "hold", "no banked roles"

    if deliverable == "baseline":
        return "escalate", "deliverable regressed to baseline while roles banked"
    if deliverable == "invalid":
        return "escalate", "deliverable verdict invalid"
    if deliverable == "tie" and len(banked) >= 3:
        return "escalate", "deliverable tie with multiple role banks — judge split"

    if deliverable in ("candidate", "tie"):
        return "promote", None

    return "hold", f"deliverableOutcome={deliverable!r}"


def load_prior_overlay(suite_id: str, team_id: str) -> dict[str, Any] | None:
    path = CHAMPIONS_DIR / suite_id / f"{team_id}.json"
    if not path.exists():
        return None
    return json.loads(path.read_text())


def build_overlay(
    *,
    suite_id: str,
    team_id: str,
    round_no: int,
    compare_record: dict[str, Any],
    baseline_lab: Path,
    candidate_lab: Path,
    alln: Path,
    prior: dict[str, Any] | None,
) -> dict[str, Any]:
    banked = set(compare_record.get("bankedRoles") or [])
    base_workers = load_workers(baseline_lab)
    cand_workers = load_workers(candidate_lab)
    prior_roles = (prior or {}).get("roles") or {}

    roles: dict[str, Any] = {}
    for rkey in sorted(set(base_workers) | set(cand_workers) | set(prior_roles)):
        if rkey in banked and rkey in cand_workers:
            worker = cand_workers[rkey]
            provenance = "banked"
            source_lab = candidate_lab.name
        elif rkey in prior_roles and prior_roles[rkey].get("provenance") == "banked":
            worker = cand_workers.get(rkey) or base_workers.get(rkey) or {}
            provenance = "banked"
            source_lab = prior_roles[rkey].get("sourceLab", baseline_lab.name)
        else:
            worker = base_workers.get(rkey) or cand_workers.get(rkey) or {}
            provenance = "incumbent"
            source_lab = baseline_lab.name

        skill_id = worker.get("skillId") or rkey.split("#")[0]
        snapshot = worker.get("resolvedWorkerPromptSnapshot") or ""
        builtin = fetch_skill_template(alln, skill_id)
        template = extract_skill_template(snapshot, builtin)
        template_changed = template.strip() != builtin.strip()
        lab_skill_id = f"lab_{team_id}_r{round_no}_{skill_id}" if template_changed else skill_id

        roles[rkey] = {
            "skillId": skill_id,
            "instanceIndex": worker.get("instanceIndex"),
            "skillName": worker.get("skillName"),
            "labSkillId": lab_skill_id,
            "provenance": provenance,
            "bankedAtRound": round_no - 1 if provenance == "banked" and rkey in banked else prior_roles.get(rkey, {}).get("bankedAtRound"),
            "sourceLab": source_lab,
            "template": template,
            "templateHash": hashlib.sha256(template.encode()).hexdigest()[:16],
            "templateChangedFromBuiltIn": template_changed,
        }

    lab_team_id = f"lab_{team_id}_r{round_no}"
    overlay = {
        "schemaVersion": 2,
        "suiteId": suite_id,
        "teamId": team_id,
        "round": round_no,
        "labTeamId": lab_team_id,
        "baseTeamId": team_id,
        "promotedAt": datetime.now(timezone.utc).isoformat(),
        "promotedFromCompare": str(compare_record.get("_path", "")),
        "promotedFromCandidateLab": candidate_lab.name,
        "promotedFromBaselineLab": baseline_lab.name,
        "bankedRoles": sorted(banked),
        "promotionClass": "quality",
        "roles": roles,
    }
    overlay["championConfigHash"] = compare_record.get("championConfigHash")
    overlay["candidateConfigHash"] = compare_record.get("candidateConfigHash")
    overlay["configHash"] = config_hash(
        overlay,
        deployed_team_id=lab_team_id if overlay_material_delta(overlay) else team_id,
        arm="champion",
    )
    return overlay


def write_skill_patch(overlay: dict[str, Any], path: Path) -> bool:
    """Reviewable patch for SkillCatalog — only roles that differ from built-in."""
    changed = {
        rkey: role
        for rkey, role in overlay["roles"].items()
        if role.get("templateChangedFromBuiltIn") and role.get("provenance") == "banked"
    }
    if not changed:
        return False
    patch = {
        "schemaVersion": 1,
        "suiteId": overlay["suiteId"],
        "teamId": overlay["teamId"],
        "round": overlay["round"],
        "promotedAt": overlay["promotedAt"],
        "evidence": overlay.get("promotedFromCompare"),
        "skills": [
            {
                "skillId": role["skillId"],
                "labSkillId": role["labSkillId"],
                "template": role["template"],
                "templateHash": role["templateHash"],
                "roleKey": rkey,
                "provenance": role["provenance"],
            }
            for rkey, role in sorted(changed.items())
        ],
        "note": "Reviewable patch — apply to SkillCatalog after enough clean fresh-input wins.",
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(patch, indent=2) + "\n")
    return True


def write_next_round_manifest(
    overlay: dict[str, Any],
    *,
    suite_id: str,
    round_no: int,
    promotion_record_path: Path,
    champion_overlay_path: Path,
) -> Path:
    manifest = {
        "schemaVersion": 1,
        "suiteId": suite_id,
        "teamId": overlay["teamId"],
        "round": round_no,
        "championOverlay": str(champion_overlay_path),
        "championVariant": f"champion-r{round_no}",
        "candidateVariant": f"candidate-r{round_no}",
        "championTeamId": overlay["labTeamId"],
        "candidateTeamId": overlay["baseTeamId"],
        "promotionRecord": str(promotion_record_path),
        "steps": [
            f"export ALLN_SCENARIO_CMD=\"cursor-agent -p\"  # separate from judges",
            f"python3 scripts/team_lab/scenario.py {suite_id} > /tmp/team-lab-case-r{round_no}.json",
            f"python3 scripts/team_lab/run.py --suite {suite_id} --round {round_no} "
            f"--variant champion-r{round_no} --champion-overlay {champion_overlay_path} "
            f"--case-json /tmp/team-lab-case-r{round_no}.json",
            f"python3 scripts/team_lab/advance.py requires --hypotheses-from for candidate material delta",
            "python3 scripts/team_lab/compare.py <champion_dir> <candidate_dir> --hypotheses",
            "python3 scripts/team_lab/promote.py --compare-record <candidate>/evaluation/compare-record.json ...",
        ],
    }
    out = PROMOTIONS_DIR / f"next_round_r{round_no}_{overlay['teamId']}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(manifest, indent=2) + "\n")
    return out


def promote(
    *,
    compare_record_path: Path,
    baseline_lab: Path,
    candidate_lab: Path,
    suite_id: str,
    team_id: str,
    round_no: int,
    alln: Path,
    force: bool = False,
) -> dict[str, Any]:
    record = json.loads(compare_record_path.read_text())
    record["_path"] = str(compare_record_path)

    verdict, reason = autopromote_gate(record)
    if verdict != "promote" and not force:
        raise SystemExit(f"autopromote {verdict}: {reason}")

    prior = load_prior_overlay(suite_id, team_id)
    overlay = build_overlay(
        suite_id=suite_id,
        team_id=team_id,
        round_no=round_no,
        compare_record=record,
        baseline_lab=baseline_lab,
        candidate_lab=candidate_lab,
        alln=alln,
        prior=prior,
    )

    champion_path = CHAMPIONS_DIR / suite_id / f"{team_id}.json"
    champion_path.parent.mkdir(parents=True, exist_ok=True)
    champion_path.write_text(json.dumps(overlay, indent=2) + "\n")

    patch_path = PATCHES_DIR / f"{suite_id}_{team_id}_r{round_no}.json"
    patch_written = write_skill_patch(overlay, patch_path)

    champ_hash, cand_hash = hashes_from_labs(baseline_lab, candidate_lab)
    PROMOTIONS_DIR.mkdir(parents=True, exist_ok=True)
    promo_path = PROMOTIONS_DIR / f"promotion_r{round_no}_{team_id}_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.json"
    manifest_path = write_next_round_manifest(
        overlay,
        suite_id=suite_id,
        round_no=round_no,
        promotion_record_path=promo_path,
        champion_overlay_path=champion_path,
    )

    promotion = {
        "schemaVersion": 2,
        "verdict": "promote" if verdict == "promote" else "forced",
        "promotionClass": "quality",
        "gateReason": reason,
        "round": round_no,
        "suiteId": suite_id,
        "teamId": team_id,
        "compareRecord": str(compare_record_path),
        "baselineLab": baseline_lab.name,
        "candidateLab": candidate_lab.name,
        "bankedRoles": record.get("bankedRoles"),
        "deliverableOutcome": record.get("deliverableOutcome"),
        "championConfigHash": champ_hash or record.get("championConfigHash"),
        "candidateConfigHash": cand_hash or record.get("candidateConfigHash"),
        "materialCandidateDelta": record.get("materialCandidateDelta"),
        "championOverlay": str(champion_path),
        "skillPatch": str(patch_path) if patch_written else None,
        "promotedAt": overlay["promotedAt"],
        "nextRoundManifest": str(manifest_path),
    }
    promo_path.write_text(json.dumps(promotion, indent=2) + "\n")

    return promotion


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--compare-record", type=Path, required=True)
    p.add_argument("--baseline-lab", type=Path, required=True)
    p.add_argument("--candidate-lab", type=Path, required=True)
    p.add_argument("--suite", required=True)
    p.add_argument("--team", required=True)
    p.add_argument("--round", type=int, required=True, help="round number AFTER promotion (e.g. 3 for R2→R3)")
    p.add_argument("--alln", type=Path, default=repo_alln())
    p.add_argument("--force", action="store_true", help="promote even if gate would hold/escalate")
    p.add_argument("--check-only", action="store_true", help="print gate verdict only")
    args = p.parse_args()

    if not args.alln.exists():
        raise SystemExit(f"alln not found: {args.alln}")

    record = json.loads(args.compare_record.read_text())
    verdict, reason = autopromote_gate(record)
    if args.check_only:
        print(json.dumps({"verdict": verdict, "reason": reason, "bankedRoles": record.get("bankedRoles")}, indent=2))
        return 0 if verdict == "promote" else 1

    promo = promote(
        compare_record_path=args.compare_record,
        baseline_lab=args.baseline_lab,
        candidate_lab=args.candidate_lab,
        suite_id=args.suite,
        team_id=args.team,
        round_no=args.round,
        alln=args.alln,
        force=args.force,
    )
    print(json.dumps(promo, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
