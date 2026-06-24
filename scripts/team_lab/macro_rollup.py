#!/usr/bin/env python3
"""Roll up per-case macro verdicts from manifest.jsonl into one bundle verdict.

    python3 scripts/team_lab/macro_rollup.py \\
        --manifest .lab/macro-evidence/manifest.jsonl \\
        --suite bug_hunt_necessity_v1 \\
        --added-role trace_mapper#0

Reads `.lab/macro-evidence/manifest.jsonl`, validates the bundle, and emits an
aggregate macro verdict with honest freshInputCount (= unique manifest rows).
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from compare import _contract_green  # noqa: E402
from macro_schema import (  # noqa: E402
    MACRO_ADD_MIN_INPUTS,
    compare_cost_margin,
    dedupe_claim_refs,
    macro_promote_gate,
    macro_verdict_template,
    seat_margin_verdict,
)


def resolve_path(raw: str) -> Path:
    path = Path(raw)
    if not path.is_absolute():
        path = REPO / path
    return path.resolve()


def load_manifest(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        raise SystemExit(f"manifest not found: {path}")
    rows: list[dict[str, Any]] = []
    for line_no, line in enumerate(path.read_text().splitlines(), start=1):
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError as e:
            raise SystemExit(f"manifest line {line_no}: invalid JSON: {e}") from e
    if not rows:
        raise SystemExit(f"manifest empty: {path}")
    return rows


def load_case_record(row: dict[str, Any]) -> dict[str, Any]:
    macro_path = resolve_path(row["macroVerdict"])
    if not macro_path.exists():
        raise SystemExit(f"missing macro verdict: {macro_path}")
    verdict = json.loads(macro_path.read_text())
    baseline_lab = resolve_path(row.get("baselineLab") or verdict.get("arm", {}).get("baselineLab", ""))
    candidate_lab = resolve_path(row.get("candidateLab") or verdict.get("arm", {}).get("candidateLab", ""))
    if not baseline_lab.is_dir():
        raise SystemExit(f"baseline lab not found: {baseline_lab}")
    if not candidate_lab.is_dir():
        raise SystemExit(f"candidate lab not found: {candidate_lab}")
    ok_b, why_b = _contract_green(baseline_lab)
    if not ok_b:
        raise SystemExit(f"baseline contract not green ({baseline_lab.name}): {why_b}")
    ok_c, why_c = _contract_green(candidate_lab)
    if not ok_c:
        raise SystemExit(f"candidate contract not green ({candidate_lab.name}): {why_c}")
    return {
        "manifestRow": row,
        "verdict": verdict,
        "macroPath": macro_path,
        "baselineLab": baseline_lab,
        "candidateLab": candidate_lab,
    }


def aggregate_deliverable(counts: Counter[str]) -> str:
    candidate = counts.get("candidate", 0)
    baseline = counts.get("baseline", 0)
    tie = counts.get("tie", 0)
    if candidate > baseline and candidate > tie:
        return "candidate"
    if baseline > candidate and baseline >= tie:
        return "baseline"
    if tie > candidate and tie > baseline:
        return "tie"
    if candidate == baseline and candidate > 0:
        return "tie"
    return "tie"


def rollup_bundle(
    cases: list[dict[str, Any]],
    *,
    suite_id: str,
    macro_operation: str,
    added_roles: list[str],
) -> dict[str, Any]:
    suite_ids: set[str] = set()
    operations: set[str] = set()
    role_sets: set[tuple[str, ...]] = set()
    case_ids: list[str] = []
    deliverable_counts: Counter[str] = Counter()
    case_outcomes: list[dict[str, Any]] = []
    vnrc_candidate_only: list[str] = []
    suppressed_all: list[str] = []
    preflight_fallbacks: list[str] = []
    cost_baseline = {"durationMs": 0, "contractScore": 1.0, "fsBypass": False, "workerTimeouts": 0}
    cost_candidate = {"durationMs": 0, "contractScore": 1.0, "fsBypass": False, "workerTimeouts": 0}

    for item in cases:
        v = item["verdict"]
        case_id = v.get("caseId") or item["manifestRow"].get("caseId")
        if not case_id:
            raise SystemExit("case missing caseId in manifest or macro verdict")
        if case_id in case_ids:
            raise SystemExit(f"duplicate case in bundle: {case_id}")
        case_ids.append(case_id)

        sid = v.get("suiteId")
        if sid:
            suite_ids.add(sid)
        op = v.get("macroOperation") or "forward_select"
        operations.add(op)
        added = tuple(v.get("arm", {}).get("addedRoles") or [])
        if added:
            role_sets.add(added)

        if v.get("judgeMode") != "live" or not v.get("evidenceValid"):
            raise SystemExit(f"{case_id}: compose must use live judges (evidenceValid)")
        if not v.get("sameInput"):
            raise SystemExit(f"{case_id}: sameInput must be true")

        outcome = v.get("deliverableOutcome") or "tie"
        deliverable_counts[outcome] += 1
        suppressed = (v.get("writerDisposition") or {}).get("value_suppressed") or []
        vnrc_c = (v.get("vnrcDelta") or {}).get("candidateOnly") or []
        fallbacks = (v.get("preflightFallbacks") or {}).get("candidate") or []
        for fb in fallbacks:
            if fb not in preflight_fallbacks:
                preflight_fallbacks.append(fb)

        case_outcomes.append(
            {
                "caseId": case_id,
                "deliverableOutcome": outcome,
                "seatMargin": v.get("seatMargin"),
                "vnrcCandidateOnly": len(dedupe_claim_refs(vnrc_c)),
                "valueSuppressedCount": len(dedupe_claim_refs(suppressed)),
                "macroVerdict": str(item["macroPath"]),
            }
        )
        vnrc_candidate_only.extend(vnrc_c)
        suppressed_all.extend(suppressed)

        ledger = v.get("costLedger") or {}
        for key, arm in (("baseline", ledger.get("baseline")), ("candidate", ledger.get("candidate"))):
            if not arm:
                continue
            bucket = cost_baseline if key == "baseline" else cost_candidate
            for field in ("durationMs", "workerTimeouts"):
                if arm.get(field):
                    bucket[field] = (bucket.get(field) or 0) + int(arm[field])

    vnrc_candidate_only = dedupe_claim_refs(vnrc_candidate_only)
    suppressed_all = dedupe_claim_refs(suppressed_all)
    suppressed_raw_total = sum(
        len((c["verdict"].get("writerDisposition") or {}).get("value_suppressed") or [])
        for c in cases
    )

    if len(suite_ids) > 1:
        raise SystemExit(f"mixed suites in bundle: {sorted(suite_ids)}")
    if suite_id and suite_ids and suite_id not in suite_ids:
        raise SystemExit(f"expected suite {suite_id!r}, got {sorted(suite_ids)}")
    bundle_suite = suite_id or (next(iter(suite_ids)) if suite_ids else "")

    if len(operations) > 1:
        raise SystemExit(f"mixed macro operations: {sorted(operations)}")
    bundle_op = macro_operation if macro_operation in operations or not operations else next(iter(operations))
    if macro_operation and operations and macro_operation not in operations:
        raise SystemExit(f"expected macro operation {macro_operation!r}, got {sorted(operations)}")

    if len(role_sets) > 1:
        raise SystemExit(f"mixed added roles: {role_sets}")
    bundle_roles = list(added_roles) if added_roles else (list(next(iter(role_sets))) if role_sets else [])
    if added_roles and role_sets:
        expected = tuple(added_roles)
        if role_sets != {expected}:
            raise SystemExit(f"expected added roles {added_roles}, got {sorted(role_sets)}")

    fresh_input_count = len(cases)
    for row in (c["manifestRow"] for c in cases):
        row_fresh = int(row.get("freshInputCount") or 0)
        if row_fresh not in (0, 1):
            raise SystemExit(
                f"manifest row freshInputCount={row_fresh} for {row.get('caseId')}; "
                "per-case composes must record 1"
            )

    agg_deliverable = aggregate_deliverable(deliverable_counts)
    cost_margin = compare_cost_margin(cost_baseline, cost_candidate)
    seat_margin = seat_margin_verdict(
        deliverable=agg_deliverable,
        cost_margin=cost_margin,
        vnrc_candidate_only=len(vnrc_candidate_only),
        macro_operation=bundle_op,
    )

    record = macro_verdict_template(suite_id=bundle_suite, macro_operation=bundle_op)
    first = cases[0]["verdict"]
    arm0 = first.get("arm") or {}
    record.update(
        {
            "promotionClass": "composition",
            "verdict": "hold",
            "arm": {
                "baselineRoster": arm0.get("baselineRoster", ""),
                "candidateRoster": arm0.get("candidateRoster", ""),
                "baselineLab": "bundle",
                "candidateLab": "bundle",
                "addedRoles": bundle_roles,
                "removedRoles": [],
            },
            "caseId": None,
            "sameInput": True,
            "caseOutcomes": case_outcomes,
            "deliverableOutcome": agg_deliverable,
            "vnrcDelta": {
                "baselineOnly": [],
                "candidateOnly": vnrc_candidate_only,
                "shared": [],
            },
            "writerDisposition": {
                "no_value": [],
                "value_suppressed": suppressed_all,
                "noise_correctly_dropped": [],
            },
            "costLedger": {"baseline": cost_baseline, "candidate": cost_candidate},
            "seatMargin": seat_margin,
            "freshInputCount": fresh_input_count,
            "evidenceValid": True,
            "judgeMode": "live",
            "preflightFallbacks": {"baseline": [], "candidate": preflight_fallbacks},
            "rollup": {
                "manifestCases": len(cases),
                "deliverableCounts": dict(deliverable_counts),
                "candidateWinRate": round(deliverable_counts.get("candidate", 0) / fresh_input_count, 3),
                "valueSuppressedTotal": len(suppressed_all),
                "valueSuppressedRawTotal": suppressed_raw_total,
                "vnrcCandidateOnlyTotal": len(vnrc_candidate_only),
                "rolledUpAt": datetime.now(timezone.utc).isoformat(),
            },
        }
    )

    gate_verdict, gate_reason = macro_promote_gate(
        record, macro_operation=bundle_op, fresh_input_count=fresh_input_count
    )
    if len(suppressed_all) > 0 and bundle_op in ("add", "forward_select"):
        record["verdict"] = "hold"
        roles = ", ".join(bundle_roles) or "added seat(s)"
        record["gateReason"] = (
            f"Macro signal present, but writer suppression blocks ADD until synthesis carries "
            f"specialist-only evidence ({len(suppressed_all)} suppressed candidate-only claims "
            f"across {fresh_input_count} inputs; roles: {roles})"
        )
        record["reason"] = record["gateReason"]
    elif gate_verdict in ("add", "remove", "merge"):
        record["verdict"] = gate_verdict
        record["gateReason"] = gate_reason
        record["reason"] = gate_reason
    else:
        record["verdict"] = "hold"
        record["gateReason"] = gate_reason
        record["reason"] = gate_reason

    if fresh_input_count < MACRO_ADD_MIN_INPUTS and record["verdict"] == "add":
        record["verdict"] = "hold"
        record["gateReason"] = f"ADD needs >={MACRO_ADD_MIN_INPUTS} fresh necessity inputs (have {fresh_input_count})"
        record["reason"] = record["gateReason"]

    return record


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=REPO / ".lab/macro-evidence/manifest.jsonl")
    p.add_argument("--suite", required=True)
    p.add_argument("--added-role", action="append", default=[], dest="added_roles")
    p.add_argument("--macro-operation", default="forward_select")
    p.add_argument("--out", type=Path, help="default: .lab/macro-evidence/rollup_<suite>.json")
    args = p.parse_args()

    rows = load_manifest(args.manifest.resolve())
    cases = [load_case_record(row) for row in rows]
    out = rollup_bundle(
        cases,
        suite_id=args.suite,
        macro_operation=args.macro_operation,
        added_roles=args.added_roles,
    )

    out_path = args.out or (REPO / ".lab/macro-evidence" / f"rollup_{args.suite}.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(out, indent=2) + "\n")

    rollup = out.get("rollup") or {}
    print(
        json.dumps(
            {
                "verdict": out["verdict"],
                "gateReason": out.get("gateReason"),
                "freshInputCount": out["freshInputCount"],
                "deliverableOutcome": out["deliverableOutcome"],
                "deliverableCounts": rollup.get("deliverableCounts"),
                "candidateWinRate": rollup.get("candidateWinRate"),
                "valueSuppressedTotal": rollup.get("valueSuppressedTotal"),
                "candidatePreflightFallbacks": (out.get("preflightFallbacks") or {}).get("candidate"),
                "path": str(out_path),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
