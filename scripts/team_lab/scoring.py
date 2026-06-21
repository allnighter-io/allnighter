"""Shared team-lab scoring helpers — MCP-first, FS diff-oracle only."""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

STALE_CLAIM_RE = re.compile(
    r"(round\s+\d+\s+(?:didn'?t|did not|hasn'?t|never)\s+complete|"
    r"round\s+\d+\s+in[- ]progress|"
    r"unfinished|"
    r"stalled\s+round|"
    r"unverified\s+(?:fix|run))",
    re.IGNORECASE,
)


def normalize_worker_id(worker_id: str) -> str:
    wid = worker_id.replace(".answer", "").removesuffix(".answer.md")
    if "#" in wid:
        return wid
    m = re.match(r"^(.+)_(\d+)$", wid)
    if m:
        return f"{m.group(1)}#{m.group(2)}"
    return wid


def load_team_result(lab_dir: Path) -> dict[str, Any] | None:
    path = lab_dir / "team-result.json"
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return None


def mcp_artifact_status(team_result: dict[str, Any] | None) -> dict[str, Any]:
    if not team_result:
        return {
            "ok": False,
            "workerCount": 0,
            "answerCount": 0,
            "promptSnapshots": 0,
            "hasPlan": False,
            "hasBundleMarkdown": False,
            "nonPlanWorkerCount": 0,
            "statusedAnswerCount": 0,
            "writerStatusPresent": False,
        }
    workers = team_result.get("workers", [])
    answers = team_result.get("workerAnswers", [])
    prompts = sum(1 for w in workers if w.get("resolvedWorkerPromptSnapshot"))
    answered = sum(1 for a in answers if (a.get("markdown") or "").strip())
    plan = team_result.get("plan") or {}
    plan_md = (plan.get("markdown") or "").strip() if isinstance(plan, dict) else ""
    # Terminal worker status lives in workerAnswers[].status (NOT workers[].status,
    # which the contract does not carry). Every non-plan worker must have a status so
    # a hidden/dropped answer/review worker cannot pass as a clean run.
    non_plan = [w for w in workers if w.get("purpose") != "plan"]
    statused_answers = [a for a in answers if (a.get("status") or "").strip()]
    writer_status_present = bool(isinstance(plan, dict) and (plan.get("status") or "").strip())
    return {
        "ok": prompts > 0 and answered > 0 and bool(plan_md),
        "workerCount": len(workers),
        "answerCount": answered,
        "promptSnapshots": prompts,
        "hasPlan": bool(plan_md),
        "hasBundleMarkdown": bool(plan_md),
        "nonPlanWorkerCount": len(non_plan),
        "statusedAnswerCount": len(statused_answers),
        "writerStatusPresent": writer_status_present,
    }


def load_logical_workers(lab_dir: Path) -> dict[str, dict[str, Any]]:
    """One entry per logical worker id. Prefer MCP team_result over copied journal."""
    out: dict[str, dict[str, Any]] = {}
    team_result = load_team_result(lab_dir)
    if team_result:
        workers_by_id = {w["id"]: w for w in team_result.get("workers", []) if w.get("id")}
        for ans in team_result.get("workerAnswers", []):
            wid = ans.get("workerId")
            if not wid:
                continue
            meta = workers_by_id.get(wid, {})
            text = (ans.get("markdown") or "").strip()
            if meta.get("purpose") == "plan":
                continue
            out[normalize_worker_id(wid)] = {
                "workerId": normalize_worker_id(wid),
                "skillName": meta.get("skillName") or meta.get("skillId") or wid,
                "modelId": ans.get("modelId") or meta.get("modelId"),
                "purpose": meta.get("purpose"),
                "answerText": text,
                "source": "mcp",
            }
        return out

    run_json = lab_dir / "run" / "run.json"
    if run_json.exists():
        data = json.loads(run_json.read_text())
        workers_by_id = {w["id"]: w for w in data.get("workers", [])}
        for ans in data.get("workerAnswers", []):
            wid = ans.get("workerId")
            if not wid:
                continue
            meta = workers_by_id.get(wid, {})
            if meta.get("purpose") == "plan":
                continue
            text = (ans.get("output") or ans.get("markdown") or "").strip()
            out[normalize_worker_id(wid)] = {
                "workerId": normalize_worker_id(wid),
                "skillName": meta.get("skillName") or meta.get("skillId") or wid,
                "modelId": ans.get("modelId") or meta.get("modelId"),
                "purpose": meta.get("purpose"),
                "answerText": text,
                "source": "journal",
            }
        return out

    workers_dir = lab_dir / "run" / "workers"
    if workers_dir.exists():
        for p in sorted(workers_dir.glob("*.answer.md")):
            stem = p.name.replace(".answer.md", "")
            wid = normalize_worker_id(stem)
            out[wid] = {
                "workerId": wid,
                "skillName": wid,
                "modelId": None,
                "purpose": None,
                "answerText": p.read_text().strip(),
                "source": "filesystem",
            }
    return out


def load_writer_bundle(lab_dir: Path) -> tuple[str, str]:
    team_result = load_team_result(lab_dir)
    if team_result:
        plan = team_result.get("plan") or {}
        if isinstance(plan, dict):
            md = (plan.get("markdown") or "").strip()
            if md:
                return md, "mcp"
    for candidate in (lab_dir / "run" / "bundle.md", lab_dir / "run" / "master_plan.md"):
        if candidate.exists() and candidate.stat().st_size > 0:
            return candidate.read_text(), "journal"
    return "", "missing"


def score_run_contract(
    lab_dir: Path,
    *,
    status: str,
    result_ok: bool,
    journal_copied: bool,
    expected_run_id: str | None = None,
) -> dict[str, Any]:
    mcp = mcp_artifact_status(load_team_result(lab_dir))
    scoring_source = "mcp" if mcp["ok"] else ("journal" if journal_copied else "none")
    fs_bypass = scoring_source != "mcp"

    floor_ok = False
    floor_path = lab_dir / "floor-show.json"
    if floor_path.exists() and expected_run_id:
        try:
            floor = json.loads(floor_path.read_text())
            floor_run_id = floor.get("runId") or (floor.get("run") or {}).get("id")
            floor_ok = floor_run_id == expected_run_id
        except (json.JSONDecodeError, OSError):
            floor_ok = False

    # Every assigned answer/review worker must have a visible terminal status, and the
    # writer status must be present. This is the "failed/timed-out workers were not
    # hidden" rubric item — a dropped worker would make statusedAnswerCount < nonPlanWorkerCount.
    worker_status_ok = (
        mcp["nonPlanWorkerCount"] > 0
        and mcp["statusedAnswerCount"] == mcp["nonPlanWorkerCount"]
        and mcp["writerStatusPresent"]
    )

    checks: list[dict[str, Any]] = []
    checks.append({"name": "terminal_status", "ok": status in {"completed", "failed", "cancelled", "interrupted"}})
    checks.append({"name": "team_result_retrieved", "ok": result_ok})
    checks.append({"name": "mcp_worker_prompts", "ok": mcp["promptSnapshots"] > 0})
    checks.append({"name": "mcp_worker_answers", "ok": mcp["answerCount"] > 0})
    checks.append({"name": "mcp_worker_status", "ok": worker_status_ok})
    checks.append({"name": "mcp_plan_markdown", "ok": mcp["hasPlan"]})
    checks.append({"name": "floor_show_run_id", "ok": floor_ok or not expected_run_id})
    checks.append({"name": "pure_mcp_scoring", "ok": not fs_bypass})
    checks.append({"name": "journal_copied_for_diff", "ok": journal_copied, "scored": False})

    scored_checks = [c for c in checks if c.get("scored", True)]
    raw_score = sum(1 for c in scored_checks if c["ok"]) / len(scored_checks)
    run_contract_score = round(raw_score, 3)
    # Spec gate: team quality is interpretable only when the run-contract lane is green
    # (fsBypass=false, runContractScore >= 0.95) and the run actually completed.
    team_quality_withheld = fs_bypass or status != "completed" or run_contract_score < 0.95

    out = {
        "runContractScore": run_contract_score,
        "checks": checks,
        "fsBypass": fs_bypass,
        "journalCopiedForDiff": journal_copied,
        "scoringSource": scoring_source,
        "teamQualityWithheld": team_quality_withheld,
        "teamQualityAuthoritative": False,
        "teamQualityWithheldReason": (
            "fsBypass: scoring relied on copied journal, not pure MCP"
            if fs_bypass
            else (
                "run not completed"
                if status != "completed"
                else (
                    f"run contract {run_contract_score} < 0.95 (substrate not fully truthful)"
                    if run_contract_score < 0.95
                    else None
                )
            )
        ),
        "teamQualityNote": (
            "Heuristic v1 — not authoritative for TeamCatalog mutations until LLM rubric ships"
        ),
        "mcpArtifactStatus": mcp,
    }
    eval_dir = lab_dir / "evaluation"
    eval_dir.mkdir(exist_ok=True)
    (eval_dir / "run-contract-score.json").write_text(json.dumps(out, indent=2))
    return out


def worker_facts(worker_id: str, text: str) -> dict[str, Any]:
    """Deterministic FACTS about a worker output — never a quality judgment.

    Quality is decided by LLM judges (compare.py). Keyword/structure scoring was
    removed: it rewarded the template words the prompts already mandate (Goodhart),
    so it optimized for theater. The only deterministic claim we make is "did this
    worker return real content," which is truth, not taste.
    """
    return {
        "workerId": worker_id,
        "chars": len(text),
        "failedOrEmpty": len(text.strip()) < 80,
    }


def check_writer_consistency(lab_dir: Path, writer_text: str) -> dict[str, Any]:
    issues: list[dict[str, str]] = []
    exp_path = lab_dir / "experiment.json"
    exp = json.loads(exp_path.read_text()) if exp_path.exists() else {}
    run_status = (exp.get("run") or {}).get("status")
    round_no = exp.get("round")
    variant = exp.get("variant", "")

    if run_status == "completed":
        for match in STALE_CLAIM_RE.finditer(writer_text):
            issues.append(
                {
                    "kind": "stale_status_claim",
                    "snippet": match.group(0),
                    "detail": f"run completed (round {round_no} variant {variant}) but writer repeats in-progress language",
                }
            )
        if re.search(rf"round\s+{round_no}\s+(?:didn'?t|did not|hasn'?t)\s+complete", writer_text, re.I):
            issues.append(
                {
                    "kind": "contradicts_current_run",
                    "snippet": f"round {round_no}",
                    "detail": "writer claims current round incomplete though experiment.json says completed",
                }
            )

    contract_path = lab_dir / "evaluation" / "run-contract-score.json"
    if contract_path.exists():
        contract = json.loads(contract_path.read_text())
        if contract.get("fsBypass"):
            if re.search(r"fsBypass\s*=\s*false|fsBypass:\s*false|no fs bypass", writer_text, re.I):
                issues.append(
                    {
                        "kind": "contradicts_artifacts",
                        "snippet": "fsBypass=false",
                        "detail": "writer claims no fs bypass but run-contract score recorded fsBypass=true",
                    }
                )

    return {
        "ok": len(issues) == 0,
        "issueCount": len(issues),
        "issues": issues[:20],
    }


def evaluate_team_quality(lab_dir: Path) -> dict[str, Any]:
    """Package artifacts + deterministic TRUTH checks. Quality is NOT scored here.

    There is no deterministic quality number any more — judgment is deferred to the
    two-judge blind A/B in compare.py. What stays deterministic is truth: did each
    worker return content (failedOrEmpty), is the writer bundle present, and does it
    contradict the run artifacts (writer consistency). `judgePending` marks that the
    quality verdict is owned by the judges, not this file.
    """
    contract_path = lab_dir / "evaluation" / "run-contract-score.json"
    contract = json.loads(contract_path.read_text()) if contract_path.exists() else {}
    # A run whose substrate lied is not worth judging — the contract gate carries over.
    judgeable = not bool(contract.get("teamQualityWithheld"))
    withheld_reason = contract.get("teamQualityWithheldReason")

    workers = load_logical_workers(lab_dir)
    facts = [worker_facts(wid, body["answerText"]) for wid, body in sorted(workers.items())]
    writer_text, writer_source = load_writer_bundle(lab_dir)
    writer_present = {"ok": bool(writer_text.strip()), "source": writer_source, "chars": len(writer_text)}
    writer_consistency = check_writer_consistency(lab_dir, writer_text)
    failures = [w for w in facts if w["failedOrEmpty"]]

    record = {
        "evaluatorVersion": "judge-deferred-v2",
        "method": "deterministic truth checks only; quality judged by compare.py (two blind LLM judges)",
        "inputs": {"answerReviewWorkerCount": len(facts), "writerSource": writer_source},
        "outputs": {
            "workerFacts": facts,
            "writerPresent": writer_present,
            "writerConsistency": writer_consistency,
        },
    }

    out = {
        "schemaVersion": 2,
        "teamQualityScore": None,
        "judgePending": judgeable,
        "judgeNote": (
            "Quality is decided by compare.py (two blind LLM judges). No deterministic "
            "quality score is emitted — keyword scoring was removed (it was theater)."
        ),
        "teamQualityWithheld": not judgeable,
        "teamQualityWithheldReason": withheld_reason,
        "workerFacts": facts,
        "writerPresent": writer_present,
        "writerConsistency": writer_consistency,
        "workerFailures": [w["workerId"] for w in failures],
        "answerReviewWorkerCount": len(facts),
    }

    eval_dir = lab_dir / "evaluation"
    eval_dir.mkdir(exist_ok=True)
    (eval_dir / "worker-facts.json").write_text(json.dumps(out, indent=2))
    (eval_dir / "evaluator-record.json").write_text(json.dumps(record, indent=2))
    return out
