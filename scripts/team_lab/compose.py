#!/usr/bin/env python3
"""Macro composition compare — deliverable A/B + cost ledger + VNRC for roster changes.

    python3 scripts/team_lab/compose.py <baseline_lab> <candidate_lab> \\
        --suite bug_hunt_necessity_v1 --macro-operation forward_select --round 1 --mock

Structural arms cannot use per-worker blind compare (Slice 1). Macro uses deliverable
A/B as the primary decider, supplemented by VNRC pre-filter and cost ledger.

See docs/phases/Team_Lab_Composition_And_Seat_Economics.md (LAB-C03).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import judge as J  # noqa: E402
from compare import _contract_green, _load_run  # noqa: E402
from macro_schema import (  # noqa: E402
    compare_cost_margin,
    infer_writer_disposition,
    macro_promote_gate,
    macro_verdict_template,
    seat_margin_verdict,
    validate_macro_verdict,
    vnrc_delta_from_labs,
    cost_ledger_arm,
)


def deliverable_outcome(
    baseline_dir: Path,
    candidate_dir: Path,
    backends: list[J.Backend],
) -> tuple[str, list[dict[str, Any]], str]:
    base, cand = _load_run(baseline_dir), _load_run(candidate_dir)
    task = cand["task"] or base["task"]
    if not base["plan_markdown"] or not cand["plan_markdown"]:
        return "tie", [], "missing plan markdown"
    input_hash = hashlib.sha256(task.encode()).hexdigest()[:12]
    blinded = J.blind_pair(
        base["plan_markdown"], cand["plan_markdown"], seed=f"{input_hash}:__macro_deliverable__"
    )
    prompt = J.deliverable_prompt(task, blinded)
    verdicts = [J.judge_pair(be, prompt, blinded) for be in backends]
    winners = [v.get("resolved") for v in verdicts if v.get("resolved") in ("baseline", "candidate", "tie")]
    if len(winners) == 2 and winners[0] == winners[1] and winners[0] != "tie":
        outcome = winners[0]
    elif "candidate" in winners and "baseline" not in winners:
        outcome = "candidate"
    elif "baseline" in winners and "candidate" not in winners:
        outcome = "baseline"
    else:
        outcome = "tie"
    return outcome, verdicts, input_hash


def compose_macro(
    baseline_dir: Path,
    candidate_dir: Path,
    backends: list[J.Backend],
    *,
    suite_id: str,
    macro_operation: str,
    fresh_input_count: int,
    added_roles: list[str] | None = None,
    removed_roles: list[str] | None = None,
) -> dict[str, Any]:
    base, cand = _load_run(baseline_dir), _load_run(candidate_dir)
    judge_mode = "mock" if any(isinstance(b, J.MockBackend) for b in backends) else "live"

    for d in (baseline_dir, candidate_dir):
        ok, why = _contract_green(d)
        if not ok:
            raise SystemExit(f"refusing macro compose: {d.name} run-contract not green ({why})")

    same_input = base["task"] == cand["task"] and base["task"] != ""
    if not same_input:
        raise SystemExit("refusing macro compose: baseline and candidate must share the same input")

    outcome, deliverable_verdicts, input_hash = deliverable_outcome(baseline_dir, candidate_dir, backends)
    vnrc = vnrc_delta_from_labs(baseline_dir, candidate_dir)
    b_cost = cost_ledger_arm(baseline_dir)
    c_cost = cost_ledger_arm(candidate_dir)
    cost_margin = compare_cost_margin(b_cost, c_cost)
    seat_margin = seat_margin_verdict(
        deliverable=outcome,
        cost_margin=cost_margin,
        vnrc_candidate_only=len(vnrc["candidateOnly"]),
        macro_operation=macro_operation,
    )

    base_team = ((base["exp"].get("teamLab") or {}).get("deployedTeamId")
                 or base["exp"].get("teamId") or "")
    cand_team = ((cand["exp"].get("teamLab") or {}).get("deployedTeamId")
                 or cand["exp"].get("teamId") or "")

    record = macro_verdict_template(suite_id=suite_id, macro_operation=macro_operation)
    record.update(
        {
            "verdict": "hold",
            "arm": {
                "baselineRoster": base_team,
                "candidateRoster": cand_team,
                "baselineLab": baseline_dir.name,
                "candidateLab": candidate_dir.name,
                "addedRoles": added_roles or [],
                "removedRoles": removed_roles or [],
            },
            "caseId": base["caseId"],
            "inputHash": input_hash,
            "sameInput": same_input,
            "deliverableOutcome": outcome,
            "vnrcDelta": vnrc,
            "writerDisposition": infer_writer_disposition(
                baseline_dir, candidate_dir, added_roles=added_roles
            ),
            "costLedger": {"baseline": b_cost, "candidate": c_cost},
            "seatMargin": seat_margin,
            "freshInputCount": fresh_input_count,
            "evidenceValid": judge_mode == "live",
            "judgeMode": judge_mode,
            "deliverableVerdicts": deliverable_verdicts,
        }
    )

    gate_verdict, gate_reason = macro_promote_gate(
        record, macro_operation=macro_operation, fresh_input_count=fresh_input_count
    )
    if gate_verdict in ("add", "remove", "merge"):
        record["verdict"] = gate_verdict
    else:
        record["verdict"] = "hold"
    record["gateReason"] = gate_reason
    record["reason"] = gate_reason

    errors = validate_macro_verdict(record)
    if errors:
        raise SystemExit(f"macro verdict invalid: {errors}")
    return record


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("baseline_lab", type=Path)
    p.add_argument("candidate_lab", type=Path)
    p.add_argument("--suite", required=True)
    p.add_argument(
        "--macro-operation",
        default="forward_select",
        choices=["add", "remove", "merge", "forward_select"],
    )
    p.add_argument("--round", type=int, default=1, help="fresh necessity input count proxy for gate")
    p.add_argument("--added-role", action="append", default=[], dest="added_roles")
    p.add_argument("--removed-role", action="append", default=[], dest="removed_roles")
    p.add_argument("--mock", action="store_true")
    args = p.parse_args()

    if args.mock:
        backends: list[J.Backend] = [
            J.MockBackend("mockA", J.mock_prefer_longer),
            J.MockBackend("mockB", J.mock_prefer_longer),
        ]
    else:
        backends = J.backends_from_env()
        if len(backends) < 2:
            raise SystemExit("set ALLN_JUDGE1_CMD and ALLN_JUDGE2_CMD, or use --mock")

    out = compose_macro(
        args.baseline_lab,
        args.candidate_lab,
        backends,
        suite_id=args.suite,
        macro_operation=args.macro_operation,
        fresh_input_count=args.round,
        added_roles=args.added_roles or None,
        removed_roles=args.removed_roles or None,
    )

    eval_dir = args.candidate_lab / "evaluation"
    eval_dir.mkdir(exist_ok=True)
    out_path = eval_dir / "macro-verdict.json"
    out_path.write_text(json.dumps(out, indent=2) + "\n")
    print(json.dumps(
        {
            "verdict": out["verdict"],
            "deliverableOutcome": out["deliverableOutcome"],
            "seatMargin": out["seatMargin"],
            "gateReason": out["gateReason"],
            "judgeMode": out["judgeMode"],
            "evidenceValid": out["evidenceValid"],
            "vnrcCandidateOnly": len(out["vnrcDelta"]["candidateOnly"]),
            "path": str(out_path),
        },
        indent=2,
    ))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
