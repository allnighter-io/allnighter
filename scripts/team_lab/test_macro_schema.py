#!/usr/bin/env python3
"""LAB-C00/C01 tests — macro verdict schema and necessity suite validation.

Run:  python3 scripts/team_lab/test_macro_schema.py
"""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from macro_schema import (  # noqa: E402
    MACRO_ADD_MIN_INPUTS,
    MACRO_REMOVE_MIN_INPUTS,
    compare_cost_margin,
    cost_ledger_arm,
    empty_cost_arm,
    extract_file_line_claims,
    claim_carried_in_plan,
    dedupe_claim_refs,
    normalize_claim_ref,
    macro_promote_gate,
    macro_verdict_template,
    validate_macro_verdict,
    validate_necessity_case,
    validate_necessity_suite,
    vnrc_delta_from_labs,
)

REPO = Path(__file__).resolve().parents[2]
NECESSITY_SUITE = REPO / "docs/team-lab/suites/bug_hunt_necessity_v1.json"

PASSES: list[str] = []
FAILS: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    (PASSES if ok else FAILS).append(f"{name}: {detail}" if detail else name)


def test_template_validates() -> None:
    rec = macro_verdict_template(suite_id="bug_hunt_necessity_v1")
    rec["deliverableOutcome"] = "tie"
    rec["evidenceValid"] = False
    rec["judgeMode"] = "mock"
    check("template.valid", not validate_macro_verdict(rec))


def test_banned_load_bearing_workers() -> None:
    case = {
        "caseId": "x",
        "prompt": "p",
        "tier": "T2",
        "requiredCapabilities": ["seam_trace"],
        "loadBearingWorkers": ["trace_mapper#0"],
    }
    errs = validate_necessity_case(case, suite_id="bug_hunt_necessity_v1")
    check("case.bans_load_bearing_workers", any("loadBearingWorkers" in e for e in errs))


def test_necessity_suite_file() -> None:
    suite = json.loads(NECESSITY_SUITE.read_text())
    errs = validate_necessity_suite(suite)
    check("necessity_suite.valid", not errs, "; ".join(errs) if errs else "ok")


def test_asymmetric_gates() -> None:
    base = macro_verdict_template(suite_id="bug_hunt_necessity_v1")
    base.update(
        {
            "judgeMode": "live",
            "evidenceValid": True,
            "sameInput": True,
            "deliverableOutcome": "candidate",
            "seatMargin": "positive",
        }
    )
    v, r = macro_promote_gate(base, macro_operation="add", fresh_input_count=MACRO_ADD_MIN_INPUTS - 1)
    check("gate.add_refuses_low_n", v == "hold" and "ADD needs" in (r or ""))

    v2, _ = macro_promote_gate(base, macro_operation="add", fresh_input_count=MACRO_ADD_MIN_INPUTS)
    check("gate.add_accepts_candidate", v2 == "add")

    base["deliverableOutcome"] = "tie"
    base["seatMargin"] = "neutral"
    v3, _ = macro_promote_gate(base, macro_operation="add", fresh_input_count=MACRO_ADD_MIN_INPUTS)
    check("gate.add_refuses_tie_neutral", v3 == "hold")

    rem = dict(base)
    rem["deliverableOutcome"] = "tie"
    rem["seatMargin"] = "neutral"
    rem["writerDisposition"] = {"no_value": [], "value_suppressed": [], "noise_correctly_dropped": []}
    v4, r4 = macro_promote_gate(rem, macro_operation="remove", fresh_input_count=MACRO_REMOVE_MIN_INPUTS - 1)
    check("gate.remove_refuses_low_n", v4 == "hold" and "REMOVE needs" in (r4 or ""))

    v5, _ = macro_promote_gate(rem, macro_operation="remove", fresh_input_count=MACRO_REMOVE_MIN_INPUTS)
    check("gate.remove_accepts_tie_neutral", v5 == "remove")

    suppressed = dict(rem)
    suppressed["writerDisposition"]["value_suppressed"] = ["Foo.swift:12"]
    v6, r6 = macro_promote_gate(suppressed, macro_operation="remove", fresh_input_count=MACRO_REMOVE_MIN_INPUTS)
    check("gate.remove_blocks_suppressed", v6 == "hold" and "value_suppressed" in (r6 or ""))


def test_vnrc_corroboration_shared() -> None:
    root = Path(tempfile.mkdtemp(prefix="macro_vnrc_"))
    try:
        base = root / "base"
        cand = root / "cand"
        for d in (base, cand):
            d.mkdir()
            (d / "team-result.json").write_text(
                json.dumps(
                    {
                        "workerAnswers": [
                            {"workerId": "a", "markdown": "see Packages/Foo.swift:42 for owner"}
                        ],
                        "plan": {"markdown": ""},
                    }
                )
            )
        # candidate adds extra line pin
        cand_tr = json.loads((cand / "team-result.json").read_text())
        cand_tr["workerAnswers"].append(
            {"workerId": "b", "markdown": "harvester at Packages/Bar.swift:10 and Foo.swift:42"}
        )
        (cand / "team-result.json").write_text(json.dumps(cand_tr))
        delta = vnrc_delta_from_labs(base, cand)
        check("vnrc.shared_corroboration", "Packages/Foo.swift:42" in delta["shared"])
        check("vnrc.candidate_only", "Packages/Bar.swift:10" in delta["candidateOnly"])
    finally:
        import shutil

        shutil.rmtree(root, ignore_errors=True)


def test_cost_margin_negative_on_timeout() -> None:
    b = empty_cost_arm()
    c = empty_cost_arm()
    c["workerTimeouts"] = 3
    check("cost.margin_negative_timeouts", compare_cost_margin(b, c) == "negative")


def test_file_line_extract() -> None:
    claims = extract_file_line_claims("Owner at scripts/team_lab/run.py:413 and scoring.py:179")
    check("claims.extract", "scripts/team_lab/run.py:413" in claims)


def test_claim_ref_normalization() -> None:
    repo = REPO
    abs_claim = f"{repo}/scripts/team_lab/run.py:373"
    deduped = dedupe_claim_refs([abs_claim, "scripts/team_lab/run.py:373", "run.py:373"], repo_root=repo)
    check("claims.dedupe_path_variants", len(deduped) == 1)
    check(
        "claims.normalize_line_range",
        normalize_claim_ref("scoring.py:178-182", repo_root=repo) == "scoring.py:178",
    )


def test_claim_carried_in_plan() -> None:
    plan = {"run.py:373", "MCPServer.swift:280"}
    check("plan.carried_short", claim_carried_in_plan("run.py:373", plan))
    check(
        "plan.carried_abs_variant",
        claim_carried_in_plan(f"{REPO}/scripts/team_lab/run.py:373", plan),
    )
    check("plan.missing_line", not claim_carried_in_plan("MCPServer.swift:281", plan))


def main() -> int:
    test_template_validates()
    test_banned_load_bearing_workers()
    test_necessity_suite_file()
    test_asymmetric_gates()
    test_vnrc_corroboration_shared()
    test_cost_margin_negative_on_timeout()
    test_file_line_extract()
    test_claim_ref_normalization()
    test_claim_carried_in_plan()

    print("\n".join(f"  ok   {p}" for p in PASSES))
    if FAILS:
        print("\n".join(f"  FAIL {f}" for f in FAILS))
        print(f"\n{len(PASSES)} passed, {len(FAILS)} FAILED")
        return 1
    print(f"\n{len(PASSES)} passed, 0 failed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
