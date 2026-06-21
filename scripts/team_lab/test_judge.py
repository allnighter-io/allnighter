#!/usr/bin/env python3
"""Tests for the judge decision logic and the compare pipeline (mock judges, no quota).

Run:  python3 scripts/team_lab/test_judge.py
"""
from __future__ import annotations

import json
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import judge as J  # noqa: E402
import compare as C  # noqa: E402

PASSES: list[str] = []
FAILS: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    (PASSES if ok else FAILS).append(f"{name}: {detail}" if detail else name)


def v(backend: str, resolved: str) -> dict:
    return {"backend": backend, "winner": "A", "resolved": resolved}


def test_json() -> None:
    check("extract_json.embedded",
          J.extract_json('noise {"winner":"A","x":1} trailing') == {"winner": "A", "x": 1})
    check("extract_json.none", J.extract_json("no json here") is None)


def test_blind() -> None:
    b = J.blind_pair("BASE", "CAND", seed="s1")
    # candidate sits in exactly one slot, and resolve inverts the placement correctly
    cand_slot = b.candidate_is
    check("blind.candidate_in_one_slot",
          (b.output_a == "CAND") == (cand_slot == "A") and (b.output_b == "CAND") == (cand_slot == "B"))
    check("blind.resolve_candidate", b.resolve(cand_slot) == "candidate")
    other = "B" if cand_slot == "A" else "A"
    check("blind.resolve_baseline", b.resolve(other) == "baseline")
    check("blind.resolve_tie", b.resolve("tie") == "tie")
    # deterministic for a given seed
    check("blind.deterministic", J.blind_pair("x", "y", seed="s1").candidate_is == b.candidate_is)


def test_blind_prompt_leaks_nothing() -> None:
    b = J.blind_pair("base text", "cand text", seed="z")
    p = J.worker_prompt("do the task", "Contrarian", b).lower()
    leak = any(w in p for w in ("candidate", "incumbent", "baseline", "model_opus", "model_chatgpt"))
    check("blind.prompt_has_no_identity_leak", not leak)


def test_decide_role() -> None:
    check("role.both_candidate_banks",
          J.decide_role("r", "R", [v("a", "candidate"), v("b", "candidate")]).keep_candidate)
    check("role.split_keeps_incumbent",
          not J.decide_role("r", "R", [v("a", "candidate"), v("b", "baseline")]).keep_candidate)
    check("role.tie_keeps_incumbent",
          not J.decide_role("r", "R", [v("a", "candidate"), v("b", "tie")]).keep_candidate)
    check("role.both_baseline_keeps_incumbent",
          not J.decide_role("r", "R", [v("a", "baseline"), v("b", "baseline")]).keep_candidate)
    check("role.invalid_keeps_incumbent",
          not J.decide_role("r", "R", [v("a", "candidate"), v("b", "invalid")]).keep_candidate)
    check("role.no_judges_keeps_incumbent", not J.decide_role("r", "R", []).keep_candidate)


def test_decide_compare() -> None:
    banked = J.decide_role("r1", "R1", [v("a", "candidate"), v("b", "candidate")])
    kept = J.decide_role("r2", "R2", [v("a", "baseline"), v("b", "candidate")])
    # deliverable regressed while a worker was banked -> interaction warning, but bank stands
    d = J.decide_compare([banked, kept], [v("a", "baseline"), v("b", "baseline")])
    check("compare.banks_only_unanimous", d.banked_roles == ["r1"])
    check("compare.deliverable_baseline", d.deliverable_outcome == "baseline")
    check("compare.interaction_warning_raised", d.interaction_warning)
    # clean candidate deliverable -> no warning
    d2 = J.decide_compare([banked], [v("a", "candidate"), v("b", "candidate")])
    check("compare.no_warning_when_deliverable_candidate", not d2.interaction_warning)


def test_map_roles() -> None:
    def w(skill, idx, purpose="answer", wid=None):
        return {"skillId": skill, "instanceIndex": idx, "purpose": purpose, "id": wid or f"{skill}-{idx}"}
    base = [w("inv", 0), w("contra", 0), w("plan", 0, "plan")]
    cand = [w("inv", 0), w("contra", 0), w("newrole", 0), w("plan", 0, "plan")]
    matched, unmatched = J.map_roles(base, cand)
    check("map.matches_shared_roles", sorted(k for k, _, _ in matched) == ["contra#0", "inv#0"])
    check("map.flags_structural_change", "newrole#0" in unmatched)
    check("map.excludes_plan", all("plan" not in k for k, _, _ in matched))


# ---- end-to-end compare() with mock judges -------------------------------- #


def _mk_run(d: Path, *, inv_ans: str, contra_ans: str, plan_md: str, task: str) -> None:
    (d / "evaluation").mkdir(parents=True)
    workers = [
        {"id": "w_inv", "skillId": "inv", "skillName": "Investigator", "instanceIndex": 0,
         "purpose": "answer", "resolvedWorkerPromptSnapshot": "p"},
        {"id": "w_contra", "skillId": "contra", "skillName": "Contrarian", "instanceIndex": 0,
         "purpose": "answer", "resolvedWorkerPromptSnapshot": "p"},
        {"id": "w_plan", "skillId": "plan", "purpose": "plan"},
    ]
    answers = [
        {"workerId": "w_inv", "markdown": inv_ans, "status": "done"},
        {"workerId": "w_contra", "markdown": contra_ans, "status": "done"},
    ]
    plan = {"markdown": plan_md, "status": "done", "writerWorkerId": "w_plan"}
    (d / "team-result.json").write_text(json.dumps({"workers": workers, "workerAnswers": answers, "plan": plan}))
    (d / "experiment.json").write_text(json.dumps({"caseId": "c1", "request": {"prompt": task}}))
    (d / "evaluation" / "run-contract-score.json").write_text(json.dumps({"fsBypass": False, "runContractScore": 1.0}))


def test_compare_e2e() -> None:
    root = Path(tempfile.mkdtemp(prefix="judge_e2e_"))
    try:
        base = root / "baseline"
        cand = root / "candidate"
        # candidate's investigator answer is LONGER (mock prefers longer -> banked);
        # contrarian shorter (-> not banked); deliverable longer (-> candidate).
        _mk_run(base, inv_ans="short inv", contra_ans="a long contrarian answer here",
                plan_md="short plan", task="same task")
        _mk_run(cand, inv_ans="a much longer investigator answer with detail",
                contra_ans="short", plan_md="a much longer and richer final plan body", task="same task")

        backends = [J.MockBackend("mockA", J.mock_prefer_longer), J.MockBackend("mockB", J.mock_prefer_longer)]
        out = C.compare(base, cand, backends)
        check("e2e.same_input_true", out["sameInput"])
        check("e2e.mock_mode_marked", out["judgeMode"] == "mock")
        check("e2e.mock_not_evidence", out["evidenceValid"] is False)
        check("e2e.banks_investigator", out["bankedRoles"] == ["inv#0"], str(out["bankedRoles"]))
        check("e2e.deliverable_candidate", out["deliverableOutcome"] == "candidate", out["deliverableOutcome"])
        check("e2e.no_interaction_warning", not out["interactionWarning"])
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_compare_refuses_different_input() -> None:
    root = Path(tempfile.mkdtemp(prefix="judge_diff_input_"))
    try:
        base = root / "baseline"
        cand = root / "candidate"
        _mk_run(base, inv_ans="base inv", contra_ans="base contra",
                plan_md="base plan", task="task one")
        _mk_run(cand, inv_ans="cand inv", contra_ans="cand contra",
                plan_md="cand plan", task="task two")
        backends = [J.MockBackend("mockA", J.mock_prefer_longer), J.MockBackend("mockB", J.mock_prefer_longer)]
        try:
            C.compare(base, cand, backends)
            check("e2e.diff_input_refused", False, "compare returned")
        except SystemExit as e:
            check("e2e.diff_input_refused", "same non-empty input" in str(e), str(e))
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main() -> int:
    for t in (test_json, test_blind, test_blind_prompt_leaks_nothing, test_decide_role,
              test_decide_compare, test_map_roles, test_compare_e2e,
              test_compare_refuses_different_input):
        t()
    print("\n".join(f"  ok   {p}" for p in PASSES))
    if FAILS:
        print("\n".join(f"  FAIL {f}" for f in FAILS))
        print(f"\n{len(PASSES)} passed, {len(FAILS)} FAILED")
        return 1
    print(f"\n{len(PASSES)} passed, 0 failed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
