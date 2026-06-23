#!/usr/bin/env python3
"""Macro composition verdict schema, necessity-case validation, and promotion gates.

See docs/phases/Team_Lab_Composition_And_Seat_Economics.md (LAB-C00+).
"""
from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
SCHEMA_PATH = REPO / "docs/team-lab/schemas/macro-verdict-v1.json"

VALID_TIERS = frozenset({"T1", "T2", "T3"})
VALID_PROVENANCE = frozenset({"committed", "generated", "debugger_packet", "lab_failure"})
VALID_VERDICTS = frozenset({"keep", "add", "remove", "merge", "escalate", "hold"})
VALID_SEAT_MARGIN = frozenset({"positive", "neutral", "negative"})
VALID_MACRO_OPS = frozenset({"add", "remove", "merge", "forward_select"})
VALID_DISPOSITION = frozenset({"no_value", "value_suppressed", "noise_correctly_dropped"})

MACRO_ADD_MIN_INPUTS = 3
MACRO_REMOVE_MIN_INPUTS = 5

# Pre-filter only — REMOVE on redundancy still needs judge audit (spec).
FILE_LINE_RE = re.compile(
    r"([A-Za-z0-9_./-]+\.(?:swift|md|py|json|sh)):(\d{1,5})",
    re.IGNORECASE,
)


def load_schema() -> dict[str, Any]:
    return json.loads(SCHEMA_PATH.read_text())


def empty_writer_disposition() -> dict[str, list[str]]:
    return {k: [] for k in ("no_value", "value_suppressed", "noise_correctly_dropped")}


def empty_vnrc_delta() -> dict[str, list[str]]:
    return {"baselineOnly": [], "candidateOnly": [], "shared": []}


def empty_cost_arm() -> dict[str, Any]:
    return {
        "durationMs": None,
        "contractScore": None,
        "fsBypass": None,
        "workerTimeouts": 0,
        "workerCount": 0,
        "answerChars": 0,
    }


def macro_verdict_template(
    *,
    suite_id: str,
    macro_operation: str = "forward_select",
) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "promotionClass": "composition",
        "verdict": "hold",
        "macroOperation": macro_operation,
        "arm": {
            "baselineRoster": "",
            "candidateRoster": "",
            "baselineLab": "",
            "candidateLab": "",
            "addedRoles": [],
            "removedRoles": [],
        },
        "suiteId": suite_id,
        "caseId": None,
        "inputHash": None,
        "sameInput": False,
        "caseOutcomes": [],
        "deliverableOutcome": "tie",
        "vnrcDelta": empty_vnrc_delta(),
        "writerDisposition": empty_writer_disposition(),
        "costLedger": {"baseline": empty_cost_arm(), "candidate": empty_cost_arm()},
        "seatMargin": "neutral",
        "freshInputCount": 0,
        "evidenceValid": False,
        "judgeMode": "mock",
        "interactionPairsTested": [],
        "gateReason": "incomplete",
        "reason": None,
    }


def validate_macro_verdict(record: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if record.get("schemaVersion") != 1:
        errors.append("schemaVersion must be 1")
    if record.get("promotionClass") != "composition":
        errors.append("promotionClass must be composition")
    verdict = record.get("verdict")
    if verdict not in VALID_VERDICTS:
        errors.append(f"invalid verdict: {verdict!r}")
    if record.get("seatMargin") not in VALID_SEAT_MARGIN:
        errors.append(f"invalid seatMargin: {record.get('seatMargin')!r}")
    if record.get("judgeMode") not in ("live", "mock"):
        errors.append("judgeMode must be live or mock")
    op = record.get("macroOperation")
    if op and op not in VALID_MACRO_OPS:
        errors.append(f"invalid macroOperation: {op!r}")
    ledger = record.get("costLedger") or {}
    for arm in ("baseline", "candidate"):
        if arm not in ledger:
            errors.append(f"costLedger missing {arm}")
    if record.get("deliverableOutcome") not in ("baseline", "candidate", "tie"):
        errors.append("invalid deliverableOutcome")
    vnrc = record.get("vnrcDelta") or {}
    for key in ("baselineOnly", "candidateOnly", "shared"):
        if key not in vnrc:
            errors.append(f"vnrcDelta missing {key}")
    return errors


def validate_necessity_case(case: dict[str, Any], *, suite_id: str | None = None) -> list[str]:
    errors: list[str] = []
    if not case.get("caseId"):
        errors.append("caseId required")
    if not case.get("prompt"):
        errors.append("prompt required")
    tier = case.get("tier")
    if tier not in VALID_TIERS:
        errors.append(f"tier must be one of {sorted(VALID_TIERS)}")
    elif tier == "T1" and (suite_id or "").endswith("necessity"):
        errors.append("necessity suite must not include T1 cases")
    caps = case.get("requiredCapabilities")
    if not isinstance(caps, list) or not caps:
        errors.append("requiredCapabilities must be a non-empty list")
    elif any(not isinstance(c, str) or not c.strip() for c in caps):
        errors.append("requiredCapabilities entries must be non-empty strings")
    prov = case.get("provenance")
    if prov and prov not in VALID_PROVENANCE:
        errors.append(f"invalid provenance: {prov!r}")
    if "loadBearingWorkers" in case:
        errors.append("loadBearingWorkers banned on case truth — use capabilityWorkerPredictions in evaluator metadata")
    return errors


def validate_necessity_suite(suite: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    sid = suite.get("suiteId", "")
    if not sid:
        errors.append("suiteId required")
    if "necessity" not in sid:
        errors.append("necessity suite id should contain 'necessity'")
    cases = suite.get("cases") or []
    if len(cases) < 3:
        errors.append("necessity suite needs at least 3 cases")
    debuggerish = sum(
        1 for c in cases if c.get("provenance") in ("debugger_packet", "lab_failure")
    )
    if debuggerish < 1:
        errors.append("necessity suite needs at least one debugger_packet or lab_failure case")
    for i, case in enumerate(cases):
        for err in validate_necessity_case(case, suite_id=sid):
            errors.append(f"cases[{i}]: {err}")
    return errors


def extract_file_line_claims(text: str) -> set[str]:
    return {f"{m.group(1)}:{m.group(2)}" for m in FILE_LINE_RE.finditer(text or "")}


def worker_answer_text(lab_dir: Path) -> dict[str, str]:
    path = lab_dir / "team-result.json"
    if not path.exists():
        return {}
    tr = json.loads(path.read_text())
    out: dict[str, str] = {}
    for ans in tr.get("workerAnswers") or []:
        wid = ans.get("workerId")
        if wid:
            out[wid] = (ans.get("markdown") or ans.get("output") or "").strip()
    return out


def vnrc_delta_from_labs(baseline_dir: Path, candidate_dir: Path) -> dict[str, list[str]]:
    base_claims: set[str] = set()
    cand_claims: set[str] = set()
    for text in worker_answer_text(baseline_dir).values():
        base_claims |= extract_file_line_claims(text)
    for text in worker_answer_text(candidate_dir).values():
        cand_claims |= extract_file_line_claims(text)
    shared = sorted(base_claims & cand_claims)
    return {
        "baselineOnly": sorted(base_claims - cand_claims),
        "candidateOnly": sorted(cand_claims - base_claims),
        "shared": shared,
    }


def plan_claims(lab_dir: Path) -> set[str]:
    path = lab_dir / "team-result.json"
    if not path.exists():
        return set()
    tr = json.loads(path.read_text())
    plan = (tr.get("plan") or {}).get("markdown") or ""
    return extract_file_line_claims(plan)


def infer_writer_disposition(
    baseline_dir: Path,
    candidate_dir: Path,
    *,
    added_roles: list[str] | None = None,
) -> dict[str, list[str]]:
    """Heuristic pre-classification — judge audit required before REMOVE."""
    disp = empty_writer_disposition()
    vnrc = vnrc_delta_from_labs(baseline_dir, candidate_dir)
    plan = plan_claims(candidate_dir) | plan_claims(baseline_dir)
    for claim in vnrc["candidateOnly"]:
        if claim in plan:
            continue
        disp["value_suppressed"].append(claim)
    if added_roles and not vnrc["candidateOnly"] and not vnrc["shared"]:
        for role in added_roles:
            disp["no_value"].append(role)
    return disp


def cost_ledger_arm(lab_dir: Path) -> dict[str, Any]:
    arm = empty_cost_arm()
    exp_path = lab_dir / "experiment.json"
    if exp_path.exists():
        exp = json.loads(exp_path.read_text())
        run = exp.get("run") or {}
        arm["durationMs"] = run.get("durationMs")
        workers = (exp.get("preflight") or {}).get("readyWorkerCount")
        if workers is not None:
            arm["workerCount"] = int(workers)
    contract_path = lab_dir / "evaluation" / "run-contract-score.json"
    if contract_path.exists():
        c = json.loads(contract_path.read_text())
        arm["contractScore"] = c.get("runContractScore")
        arm["fsBypass"] = c.get("fsBypass")
        mcp = c.get("mcpArtifactStatus") or {}
        non_plan = mcp.get("nonPlanWorkerCount") or 0
        statused = mcp.get("statusedAnswerCount") or 0
        if non_plan and statused < non_plan:
            arm["workerTimeouts"] = non_plan - statused
    chars = sum(len(t) for t in worker_answer_text(lab_dir).values())
    arm["answerChars"] = chars
    return arm


def compare_cost_margin(baseline: dict[str, Any], candidate: dict[str, Any]) -> str:
    """Rough margin from duration + contract + timeout surface."""
    b_dur = baseline.get("durationMs") or 0
    c_dur = candidate.get("durationMs") or 0
    b_fail = (baseline.get("contractScore") or 1) < 0.95 or baseline.get("fsBypass")
    c_fail = (candidate.get("contractScore") or 1) < 0.95 or candidate.get("fsBypass")
    b_to = baseline.get("workerTimeouts") or 0
    c_to = candidate.get("workerTimeouts") or 0
    if c_fail and not b_fail:
        return "negative"
    if c_to > b_to + 1:
        return "negative"
    if c_dur and b_dur and c_dur > b_dur * 1.35:
        return "negative"
    if c_dur and b_dur and c_dur < b_dur * 0.85:
        return "positive"
    return "neutral"


def seat_margin_verdict(
    *,
    deliverable: str,
    cost_margin: str,
    vnrc_candidate_only: int,
    macro_operation: str,
) -> str:
    if deliverable == "candidate" and cost_margin != "negative":
        return "positive"
    if deliverable == "baseline":
        return "negative"
    if deliverable == "tie" and vnrc_candidate_only > 0 and cost_margin != "positive":
        return "neutral"
    if deliverable == "tie" and cost_margin == "positive" and macro_operation == "remove":
        return "negative"
    return "neutral"


def macro_promote_gate(
    record: dict[str, Any],
    *,
    macro_operation: str,
    fresh_input_count: int,
) -> tuple[str, str | None]:
    """Return (verdict, reason) for composition promotion."""
    if record.get("judgeMode") != "live" or not record.get("evidenceValid"):
        return "hold", "live evidence required for composition promotion"
    if not record.get("sameInput"):
        return "hold", "sameInput is false"
    if macro_operation not in VALID_MACRO_OPS:
        return "hold", f"unknown macro operation {macro_operation!r}"

    deliverable = record.get("deliverableOutcome")
    margin = record.get("seatMargin")
    suppressed = (record.get("writerDisposition") or {}).get("value_suppressed") or []
    vnrc_c = len((record.get("vnrcDelta") or {}).get("candidateOnly") or [])

    if macro_operation in ("add", "forward_select"):
        if fresh_input_count < MACRO_ADD_MIN_INPUTS:
            return "hold", f"ADD needs >={MACRO_ADD_MIN_INPUTS} fresh necessity inputs (have {fresh_input_count})"
        if deliverable == "candidate" and margin != "negative":
            return "add", None
        if deliverable == "tie" and vnrc_c > 0 and margin == "neutral":
            return "hold", "tie with neutral cost — insufficient to ADD"
        return "hold", f"ADD not justified (deliverable={deliverable}, margin={margin})"

    if macro_operation == "remove":
        if fresh_input_count < MACRO_REMOVE_MIN_INPUTS:
            return "hold", f"REMOVE needs >={MACRO_REMOVE_MIN_INPUTS} fresh necessity inputs (have {fresh_input_count})"
        if suppressed:
            return "hold", "value_suppressed — fix writer contract before REMOVE"
        if deliverable == "baseline":
            return "hold", "deliverable favors baseline — cannot REMOVE"
        if deliverable == "tie" and margin in ("neutral", "negative"):
            return "remove", None
        return "hold", f"REMOVE not justified (deliverable={deliverable}, margin={margin})"

    return "hold", "merge gate not implemented in v1"


def genesis_record_template(case_id: str, suite_id: str, roster_id: str) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "caseId": case_id,
        "suiteId": suite_id,
        "rosterId": roster_id,
        "contextHash": None,
        "outcome": None,
        "runContractScore": None,
        "labDir": None,
        "recordedAt": None,
    }


def write_genesis_record(path: Path, record: dict[str, Any]) -> None:
    record = dict(record)
    record["recordedAt"] = datetime.now(timezone.utc).isoformat()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(record, indent=2) + "\n")
