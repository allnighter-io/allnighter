#!/usr/bin/env python3
"""Planted-failure regression tests for the team-lab truth evaluator.

The evaluator is itself an oracle for run truth, so it needs its own kill tests:
prove it fails a bad run and permits a judgeable good one. Pure-local, no model
quota.

Run:  python3 scripts/team_lab/test_scoring.py
"""
from __future__ import annotations

import json
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scoring import (  # noqa: E402
    check_writer_consistency,
    evaluate_team_quality,
    score_run_contract,
    worker_facts,
)

# A real committed suite/case so expectedQualities resolve through the same path run.py uses.
SUITE_ID = "bug_hunt_repo_regressions_v1"
CASE_ID = "composer_paste_dead_v1"

GOOD_ANSWER = (
    "Evidence inspected: current diff and DEBUGLOG. This is a tier T3 repeated bug. "
    "The truth owner is RoutingComposer.text; the lie-prone layer is the pasteboard read. "
    "Confidence: medium. What would falsify this: a kill test using a real clipboard source. "
    "I require kill tests before any patch and recommend the isolation harness for this "
    "repeated bug. Proof. Contract. MCP. This does not claim a root cause without evidence."
)

PASSES: list[str] = []
FAILS: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    (PASSES if ok else FAILS).append(f"{name}: {detail}" if detail else name)


def make_lab(
    tmp: Path,
    *,
    status: str = "completed",
    non_plan_workers: int = 3,
    statused_answers: int | None = None,
    writer_status: str | None = "done",
    writer_text: str = "Decision. Preserve dissent; reject the weak majority. Proof boundary named.",
    answer_text: str = GOOD_ANSWER,
    with_prompts: bool = True,
    with_plan_md: bool = True,
) -> Path:
    """Build a minimal lab dir with experiment.json + team-result.json."""
    lab = tmp
    (lab / "evaluation").mkdir(parents=True, exist_ok=True)
    statused_answers = non_plan_workers if statused_answers is None else statused_answers

    workers = []
    answers = []
    for i in range(non_plan_workers):
        wid = f"model_opus#{i}"
        workers.append(
            {
                "id": wid,
                "purpose": "answer",
                "skillName": "investigator",
                "modelId": "model_opus",
                "resolvedWorkerPromptSnapshot": "prompt" if with_prompts else "",
            }
        )
        answers.append(
            {
                "workerId": wid,
                "markdown": answer_text,
                "modelId": "model_opus",
                "status": "done" if i < statused_answers else "",
            }
        )
    workers.append({"id": "model_opus#W", "purpose": "plan", "modelId": "model_opus"})
    plan = {
        "markdown": writer_text if with_plan_md else "",
        "status": writer_status or "",
        "writerWorkerId": "model_opus#W",
        "stageId": "STAGE-1",
    }
    (lab / "team-result.json").write_text(
        json.dumps({"workers": workers, "workerAnswers": answers, "plan": plan})
    )
    (lab / "floor-show.json").write_text(json.dumps({"runId": "TEST-RUN"}))
    (lab / "experiment.json").write_text(
        json.dumps(
            {
                "suiteId": SUITE_ID,
                "caseId": CASE_ID,
                "round": 1,
                "variant": "test",
                "run": {"status": status, "runId": "TEST-RUN"},
            }
        )
    )
    return lab


def score(lab: Path, status: str = "completed", run_id: str | None = "TEST-RUN") -> tuple[dict, dict]:
    contract = score_run_contract(
        lab, status=status, result_ok=True, journal_copied=True, expected_run_id=run_id
    )
    team = evaluate_team_quality(lab)
    return contract, team


def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="team_lab_test_"))
    try:
        # 1. Good run: judgeable, no deterministic score, content present.
        good = make_lab(root / "good")
        contract, team = score(good)
        check("good_run.no_deterministic_score", team["teamQualityScore"] is None)
        check("good_run.judge_pending", team["judgePending"] and not team["teamQualityWithheld"])
        check("good_run.workers_have_content", all(not w["failedOrEmpty"] for w in team["workerFacts"]))
        check("good_run.contract>=0.95", contract["runContractScore"] >= 0.95, str(contract["runContractScore"]))
        check("good_run.worker_status_check_ok",
              next(c["ok"] for c in contract["checks"] if c["name"] == "mcp_worker_status"))

        # 2. Hidden/dropped worker: one answer has no status -> worker-status check fails,
        #    contract drops below the gate, team quality is withheld.
        dropped = make_lab(root / "dropped", non_plan_workers=3, statused_answers=2)
        contract, team = score(dropped)
        check("dropped_worker.status_check_fails",
              not next(c["ok"] for c in contract["checks"] if c["name"] == "mcp_worker_status"))
        check("dropped_worker.contract<0.95", contract["runContractScore"] < 0.95, str(contract["runContractScore"]))
        check("dropped_worker.team_quality_withheld", team["teamQualityWithheld"])

        # 3. Empty worker answer -> failedOrEmpty true (truth, not taste).
        empty = worker_facts("model_x#0", "  ")
        check("empty_answer.failedOrEmpty", empty["failedOrEmpty"])

        # 4. Stale-claim writer on a completed run -> consistency issue flagged.
        stale = make_lab(root / "stale")
        score(stale)  # writes run-contract-score.json that the check reads
        consistency = check_writer_consistency(
            stale, "Round 1 didn't complete; this is an unverified fix from a stalled round."
        )
        check("stale_writer.flags_issue", not consistency["ok"] and consistency["issueCount"] > 0,
              f"issues={consistency['issueCount']}")

        # 5. fsBypass (no MCP artifacts) -> team quality withheld.
        bypass = root / "bypass"
        (bypass / "evaluation").mkdir(parents=True)
        (bypass / "experiment.json").write_text(
            json.dumps({"suiteId": SUITE_ID, "caseId": CASE_ID, "round": 1, "run": {"status": "completed"}})
        )
        contract = score_run_contract(bypass, status="completed", result_ok=False, journal_copied=True)
        check("fs_bypass.detected", contract["fsBypass"])
        check("fs_bypass.team_quality_withheld", contract["teamQualityWithheld"])
    finally:
        shutil.rmtree(root, ignore_errors=True)

    print("\n".join(f"  ok   {p}" for p in PASSES))
    if FAILS:
        print("\n".join(f"  FAIL {f}" for f in FAILS))
        print(f"\n{len(PASSES)} passed, {len(FAILS)} FAILED")
        return 1
    print(f"\n{len(PASSES)} passed, 0 failed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
