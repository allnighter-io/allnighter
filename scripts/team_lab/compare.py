#!/usr/bin/env python3
"""Round comparator — baseline run vs candidate run on the SAME input.

    python3 scripts/team_lab/compare.py <baseline_dir> <candidate_dir> [--hypotheses]
    python3 scripts/team_lab/compare.py <baseline_dir> <candidate_dir> --mock   # no quota

Two DIFFERENT-family judges (env ALLN_JUDGE1_CMD / ALLN_JUDGE2_CMD) blindly pick
the better output per worker and for the deliverable. A worker's candidate prompt
is banked only if BOTH judges agree it is better; ties go to the incumbent. The
deliverable verdict audits for interaction regressions but never vetoes a clean
per-worker win. Judges never see prompts or which side is the candidate.
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
from config import hashes_from_labs  # noqa: E402


def _load_run(lab_dir: Path) -> dict[str, Any]:
    tr = json.loads((lab_dir / "team-result.json").read_text())
    exp_path = lab_dir / "experiment.json"
    exp = json.loads(exp_path.read_text()) if exp_path.exists() else {}
    answers = {a["workerId"]: a for a in tr.get("workerAnswers", []) if a.get("workerId")}
    plan = tr.get("plan") or {}
    return {
        "dir": lab_dir,
        "workers": tr.get("workers", []),
        "answers": answers,
        "plan_markdown": (plan.get("markdown") or "").strip(),
        "task": ((exp.get("request") or {}).get("prompt") or "").strip(),
        "caseId": exp.get("caseId"),
        "exp": exp,
    }


def _contract_green(lab_dir: Path) -> tuple[bool, str]:
    path = lab_dir / "evaluation" / "run-contract-score.json"
    if not path.exists():
        return False, "no run-contract-score.json (run evaluate.py --rescore-contract first)"
    c = json.loads(path.read_text())
    if c.get("fsBypass"):
        return False, "fsBypass=true"
    if c.get("runContractScore", 0) < 0.95:
        return False, f"runContractScore {c.get('runContractScore')} < 0.95"
    return True, "green"


def _label(worker: dict[str, Any]) -> str:
    return worker.get("skillName") or worker.get("skillId") or worker.get("purpose") or worker.get("id")


from worker_health import origin_map_from_lab_dir as _origin_map_from_lab_dir
from worker_health import promotion_worker_meta


def compare(baseline_dir: Path, candidate_dir: Path, backends: list[J.Backend],
            *, with_hypotheses: bool = False) -> dict[str, Any]:
    base, cand = _load_run(baseline_dir), _load_run(candidate_dir)
    judge_mode = "mock" if any(isinstance(b, J.MockBackend) for b in backends) else "live"

    # Substrate gate — judges only run on runs the contract proved truthful.
    for d in (baseline_dir, candidate_dir):
        ok, why = _contract_green(d)
        if not ok:
            raise SystemExit(f"refusing to judge: {d.name} run-contract not green ({why})")

    # Same-input discipline: within a round, both arms must share the input.
    same_input = base["task"] == cand["task"] and base["task"] != ""
    if not same_input:
        raise SystemExit(
            "refusing to judge: baseline and candidate must use the exact same non-empty input"
        )
    input_hash = hashlib.sha256(base["task"].encode()).hexdigest()[:12]

    origin_by_skill = {
        **_origin_map_from_lab_dir(baseline_dir),
        **_origin_map_from_lab_dir(candidate_dir),
    }
    matched, unmatched = J.map_roles(
        base["workers"], cand["workers"], origin_by_skill=origin_by_skill
    )

    role_decisions: list[J.RoleDecision] = []
    hypotheses: list[dict[str, Any]] = []
    for rkey, bw, cw in matched:
        b_ans = (base["answers"].get(bw["id"], {}).get("markdown") or "").strip()
        c_ans = (cand["answers"].get(cw["id"], {}).get("markdown") or "").strip()
        if not b_ans or not c_ans:
            role_decisions.append(J.RoleDecision(rkey, _label(bw), [], False, "missing answer text"))
            continue
        blinded = J.blind_pair(b_ans, c_ans, seed=f"{input_hash}:{rkey}")
        prompt = J.worker_prompt(cand["task"] or base["task"], _label(bw), blinded)
        verdicts = [J.judge_pair(be, prompt, blinded) for be in backends]
        decision = J.decide_role(rkey, _label(bw), verdicts)
        role_decisions.append(decision)

        if with_hypotheses:
            bp = bw.get("resolvedWorkerPromptSnapshot") or ""
            cp = cw.get("resolvedWorkerPromptSnapshot") or ""
            summary = "; ".join(f"{v['backend']}:{v['resolved']}" for v in verdicts)
            try:
                raw = backends[0].run(J.hypotheses_prompt(_label(bw), bp, cp, summary))
                hyp = (J.extract_json(raw) or {}).get("hypotheses", [])
                hypotheses.append({"role": rkey, "hypotheses": hyp})
            except Exception as e:  # idea-engine is advisory; never fail the gate on it
                hypotheses.append({"role": rkey, "error": str(e)[:200]})

    # Deliverable — the unit of suspicion (audit, not veto).
    deliverable_verdicts: list[dict[str, Any]] = []
    if base["plan_markdown"] and cand["plan_markdown"]:
        blinded = J.blind_pair(base["plan_markdown"], cand["plan_markdown"], seed=f"{input_hash}:__deliverable__")
        prompt = J.deliverable_prompt(cand["task"] or base["task"], blinded)
        deliverable_verdicts = [J.judge_pair(be, prompt, blinded) for be in backends]

    decision = J.decide_compare(role_decisions, deliverable_verdicts, unmatched)

    champ_hash, cand_hash = hashes_from_labs(baseline_dir, candidate_dir)
    worker_meta = promotion_worker_meta(candidate_dir)

    return {
        "schemaVersion": 1,
        "baseline": baseline_dir.name,
        "candidate": candidate_dir.name,
        "caseId": base["caseId"],
        "inputHash": input_hash,
        "sameInput": same_input,
        "championConfigHash": champ_hash,
        "candidateConfigHash": cand_hash,
        "materialCandidateDelta": bool(champ_hash and cand_hash and champ_hash != cand_hash),
        "judges": [b.name for b in backends],
        "judgeMode": judge_mode,
        "evidenceValid": judge_mode == "live",
        "bankedRoles": decision.banked_roles,
        "deliverableOutcome": decision.deliverable_outcome,
        "interactionWarning": decision.interaction_warning,
        "unmatchedRoles": decision.unmatched_roles,
        "roleDecisions": [
            {
                "role": d.role_key,
                "label": d.role_label,
                "keepCandidate": d.keep_candidate,
                "note": d.note,
                "verdicts": d.verdicts,
            }
            for d in decision.role_decisions
        ],
        "deliverableVerdicts": deliverable_verdicts,
        "hypotheses": hypotheses,
        **worker_meta,
    }


def _write_report(out: dict[str, Any], path: Path) -> None:
    lines = [
        f"# Compare — {out['candidate']} vs {out['baseline']}",
        "",
        f"- Case: `{out['caseId']}` · input `{out['inputHash']}` · sameInput={out['sameInput']}",
        f"- Judges: {', '.join(out['judges']) or '(none)'}",
        f"- Judge mode: **{out['judgeMode']}**"
        + (" — pipeline smoke only; not evidence" if out["judgeMode"] == "mock" else ""),
        f"- Banked roles (both judges agree better): **{out['bankedRoles'] or 'none'}**",
        f"- Deliverable audit: **{out['deliverableOutcome']}**"
        + ("  ⚠️ INTERACTION WARNING" if out["interactionWarning"] else ""),
    ]
    if out["unmatchedRoles"]:
        lines.append(f"- Unmatched (structural) roles → deliverable gate only: {out['unmatchedRoles']}")
    lines += ["", "## Per-worker verdicts", ""]
    for d in out["roleDecisions"]:
        tag = "BANK candidate" if d["keepCandidate"] else "keep incumbent"
        votes = " / ".join(f"{v['backend']}={v['resolved']}" for v in d["verdicts"]) or "—"
        lines.append(f"- **{d['label']}** (`{d['role']}`): {tag} — {votes}")
    if out["hypotheses"]:
        lines += ["", "## Next-round hypotheses (non-voting idea-engine)", ""]
        for h in out["hypotheses"]:
            for item in h.get("hypotheses", []):
                lines.append(f"- `{h['role']}`: {item.get('change')} → {item.get('expected_effect')}")
    path.write_text("\n".join(lines) + "\n")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("baseline_dir", type=Path)
    p.add_argument("candidate_dir", type=Path)
    p.add_argument("--hypotheses", action="store_true", help="run the un-blind idea-engine")
    p.add_argument("--mock", action="store_true", help="use deterministic mock judges (no quota)")
    args = p.parse_args()

    if args.mock:
        # Mock judges prefer the longer output — deterministic, for pipeline smoke only.
        backends: list[J.Backend] = [J.MockBackend("mockA", J.mock_prefer_longer),
                                     J.MockBackend("mockB", J.mock_prefer_longer)]
    else:
        backends = J.backends_from_env()
        if len(backends) < 2:
            raise SystemExit("set ALLN_JUDGE1_CMD and ALLN_JUDGE2_CMD (two different model families), or use --mock")

    out = compare(args.baseline_dir, args.candidate_dir, backends, with_hypotheses=args.hypotheses)
    eval_dir = args.candidate_dir / "evaluation"
    eval_dir.mkdir(exist_ok=True)
    (eval_dir / "compare-record.json").write_text(json.dumps(out, indent=2))
    _write_report(out, eval_dir / "compare.md")
    print(json.dumps({k: out[k] for k in
                      ("bankedRoles", "deliverableOutcome", "interactionWarning",
                       "sameInput", "judges", "judgeMode", "evidenceValid",
                       "championConfigHash", "candidateConfigHash", "materialCandidateDelta")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
