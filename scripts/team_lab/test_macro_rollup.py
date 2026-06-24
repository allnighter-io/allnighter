#!/usr/bin/env python3
"""Tests for macro_rollup (synthetic fixtures, no MCP)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import macro_rollup as R  # noqa: E402


def _write_contract(lab: Path, score: float = 1.0) -> None:
    ev = lab / "evaluation"
    ev.mkdir(parents=True, exist_ok=True)
    (ev / "run-contract-score.json").write_text(
        json.dumps({"runContractScore": score, "fsBypass": False}) + "\n"
    )


def _macro_verdict(case_id: str, outcome: str, suppressed: int) -> dict:
    return {
        "schemaVersion": 1,
        "promotionClass": "composition",
        "verdict": "hold",
        "macroOperation": "forward_select",
        "arm": {
            "baselineRoster": "lite",
            "candidateRoster": "lite+trace",
            "addedRoles": ["trace_mapper#0"],
        },
        "suiteId": "bug_hunt_necessity_v1",
        "caseId": case_id,
        "sameInput": True,
        "deliverableOutcome": outcome,
        "vnrcDelta": {"baselineOnly": [], "candidateOnly": ["a:1"] * suppressed, "shared": []},
        "writerDisposition": {
            "no_value": [],
            "value_suppressed": [f"claim{i}" for i in range(suppressed)],
            "noise_correctly_dropped": [],
        },
        "costLedger": {
            "baseline": {"durationMs": 1000, "contractScore": 1.0, "fsBypass": False, "workerTimeouts": 0},
            "candidate": {"durationMs": 900, "contractScore": 1.0, "fsBypass": False, "workerTimeouts": 0},
        },
        "seatMargin": "positive",
        "freshInputCount": 1,
        "evidenceValid": True,
        "judgeMode": "live",
        "preflightFallbacks": {"candidate": ["Trace Mapper: model_cursor_auto unavailable; resolved to ChatGPT 5.5."]},
    }


def test_rollup_three_case_bundle(tmp_path: Path) -> None:
    cases = []
    for case_id, outcome, sup in (
        ("floor_show_wrong_run_v1", "tie", 8),
        ("mcp_fs_bypass_scoring_v1", "candidate", 11),
        ("cursor_composer_session_continuity_v1", "candidate", 15),
    ):
        base = tmp_path / f"base_{case_id}"
        cand = tmp_path / f"cand_{case_id}"
        base.mkdir()
        cand.mkdir()
        _write_contract(base)
        _write_contract(cand)
        macro_path = tmp_path / f"{case_id}_macro.json"
        macro_path.write_text(json.dumps(_macro_verdict(case_id, outcome, sup)) + "\n")
        cases.append(
            {
                "manifestRow": {
                    "caseId": case_id,
                    "freshInputCount": 1,
                    "macroVerdict": str(macro_path),
                    "baselineLab": str(base),
                    "candidateLab": str(cand),
                },
                "verdict": json.loads(macro_path.read_text()),
                "macroPath": macro_path,
                "baselineLab": base,
                "candidateLab": cand,
            }
        )

    out = R.rollup_bundle(
        cases,
        suite_id="bug_hunt_necessity_v1",
        macro_operation="forward_select",
        added_roles=["trace_mapper#0"],
    )
    assert out["freshInputCount"] == 3
    assert out["rollup"]["deliverableCounts"] == {"tie": 1, "candidate": 2}
    assert out["rollup"]["valueSuppressedTotal"] == 34
    assert out["verdict"] == "hold"
    assert "writer suppression blocks ADD" in (out.get("gateReason") or "")


def test_aggregate_deliverable() -> None:
    c = __import__("collections").Counter({"candidate": 2, "tie": 1})
    assert R.aggregate_deliverable(c) == "candidate"


if __name__ == "__main__":
    test_aggregate_deliverable()
    import tempfile

    with tempfile.TemporaryDirectory() as td:
        test_rollup_three_case_bundle(Path(td))
    print("ok: test_macro_rollup")
